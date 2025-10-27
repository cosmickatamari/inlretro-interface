
-- create the module's table
local action53_tsop = {}

-- import required modules
local nes = require "scripts.app.nes"
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local files = require "scripts.app.files"
local buffers = require "scripts.app.buffers"

-- file constants
local mapname = "A53"

-- local functions

local function create_header( file, prgKB, chrKB )

	--write_header( file, prgKB, chrKB, mapper, mirroring )
	nes.write_header( file, prgKB, 0, op_buffer[mapname], 0)
end


--local function wr_flash_byte(addr, value, debug)

--base is the actual NES CPU address, not the rom offset (ie $FFF0, not $7FF0)
--local function wr_bank_table(base, entries)
--Action53 not susceptible to bus conflicts, no banktable needed



--initialize mapper for dump/flash routines
local function init_mapper( debug )
	
	--//Setup as CNROM, then scroll through outer banks.
	--cpu_wr(0x5000, 0x80);   //reg select mode
	dict.nes("NES_CPU_WR", 0x5000, 0x80)

	--//   xxSSPPMM   SS-size: 0-32KB, PP-prg mode: 0,1 32KB, MM-mirror
	--cpu_wr(0x8000, 0b00000000);     //reg value 256KB inner, 32KB banks
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	--cpu_wr(0x5000, 0x81);   //outer reg select mode
	dict.nes("NES_CPU_WR", 0x5000, 0x81)
	--cpu_wr(0x8000, 0x00);   //first 32KB bank
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	--
	--cpu_wr(0x5000, 0x01);   //inner prg reg select
	dict.nes("NES_CPU_WR", 0x5000, 0x01)
	--cpu_wr(0x8000, 0x00);   //controls nothing in this size
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	--cpu_wr(0x5000, 0x00);   //chr reg select
	dict.nes("NES_CPU_WR", 0x5000, 0x00)
	--cpu_wr(0x8000, 0x00);   //first chr bank
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	--selecting CNROM means that mapper writes to $8000-FFFF will only change the CHR-RAM bank which
	--doesn't affect anything we're concerned about
	
	--enable flash writes $5000 set to 0b0 101 010 0
	dict.nes("NES_CPU_WR", 0x5000, 0x54)
	--dict.nes("NES_CPU_WR", 0x5555, 0x54)

end


--read PRG-ROM flash ID
local function prgrom_manf_id( debug )

	local rv
	init_mapper()

	if debug then print("reading PRG-ROM manf ID") end
	--A0-A14 are all directly addressable in CNROM mode
	--and mapper writes don't affect PRG banking
--address doesn't get applied to flash unless M2 is high
--prg_data-addr_oe levelshifter pin is driven by ~M2
	dict.nes("FLASH_3V_WR", 0x8AAA, 0xAA)
	dict.nes("FLASH_3V_WR", 0x8555, 0x55)
	dict.nes("FLASH_3V_WR", 0x8AAA, 0x90)
	rv = dict.nes("NES_CPU_RD", 0x8000)
	if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end	--0x01
	rv = dict.nes("NES_CPU_RD", 0x8002)
	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end	--0xDA(top), 0x5B(bot)

	--exit software
	dict.nes("FLASH_3V_WR", 0x8000, 0xF0)

end


--host flash one bank at a time...
--this is controlled from the host side one bank at a time
--but requires mapper specific firmware flashing functions
--there is super slow version commented out that doesn't require MMC3 specific firmware code
local function flash_prgrom(file, rom_size_KB, debug)

	init_mapper()

	--test some bytes
	--wr_prg_flash_byte(0x0000, 0xA5, true)
	--wr_prg_flash_byte(0x0FFF, 0x5A, true)

	print("\nProgramming PRG-ROM flash")
	--initial testing of MMC3 with no specific MMC3 flash firmware functions 6min per 256KByte = 0.7KBps


	local base_addr = 0x8000 --writes occur $8000-9FFF
	local bank_size = 32*1024 --in CNROM mode 32KB PRG bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata


	while cur_bank < total_banks do

		if (cur_bank %8 == 0) then
			print("writting PRG bank: ", cur_bank, " of ", total_banks-1)
		end

		--write the current bank to the mapper register
		--nes_cpu_wr(0x5000, 0x81); //outer reg select mode
		dict.nes("NES_CPU_WR", 0x5000, 0x81)
		--nes_cpu_wr(0x8000, bank);         //outer bank
		dict.nes("NES_CPU_WR", 0x8000, cur_bank)
		--nes_cpu_wr(0x5000, 0x54); //
		dict.nes("NES_CPU_WR", 0x5000, 0x54)


		--program the entire bank's worth of data

		--[[  This version of the code programs a single byte at a time but doesn't require 
		--	MMC3 specific functions in the firmware
		print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware MMC3 specific functions 100% host flash algo:
			--wr_prg_flash_byte(base_addr+byte_num, data, false)   --0.7KBps

			--EASIEST FIRMWARE SPEEDUP: 5x faster, create MMC3 write byte function:
			dict.nes("MMC3_PRG_FLASH_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)
			--NEXT STEP: firmware write page/bank function can use function pointer for the function above
			--	this may cause issues with more complex algos
			--	sometimes cur bank is needed 
			--	for this to work, need to have function post conditions meet the preconditions
			--	that way host intervention is only needed for bank controls
			--	Is there a way to allow for double buffering though..?
			--	YES!  just think of the bank as a complete memory
			--	this greatly simplifies things and is exactly where we want to go
			--	This is completed below outside the byte while loop @ 39KBps

			if (verify) then
				readdata = dict.nes("NES_CPU_RD", base_addr+byte_num)
				if readdata ~= data then
					print("ERROR flashing byte number", byte_num, " in bank",cur_bank, " to flash ", data, readdata)
				end
			end

			byte_num = byte_num + 1
		end
		--]]

		--Have the device write a banks worth of data
		--FAST!  13sec for 512KB = 39KBps
		flash.write_file( file, bank_size/1024, mapname, "PRGROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")

end


--dump the PRG ROM
local function dump_prgrom( file, rom_size_KB, debug )

	--PRG-ROM dump 32KB at a time in CNROM mode with supervisor register
	local KB_per_read = 32
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x80	-- $8000 PAGE

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		--select desired bank(s) to dump
		--nes_cpu_wr(0x5000, 0x81); //outer reg select mode
		--nes_cpu_wr(0x8000, bank);         //outer bank
		--nes_cpu_wr(0x5000, 0x00); //chr reg select act like CNROM
		dict.nes("NES_CPU_WR", 0x5000, 0x81)
		dict.nes("NES_CPU_WR", 0x8000, read_count)
		dict.nes("NES_CPU_WR", 0x5000, 0x54)

		--dump bank's worth of data
		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_PAGE", false )

		read_count = read_count + 1
	end

end



local function read_gift( base, len )

	local rv
	init_mapper()

	--select last bank in read only mode
	dict.nes("NES_CPU_WR", 0x5000, 0x81)
	dict.nes("NES_CPU_WR", 0x8000, 0xFF)

	local i = 0

	while i < len do 
		rv = dict.nes("NES_CPU_RD", base+i)
		io.write(string.char(rv))
		i = i+1
	end

	i = 0

	print("")

	while i < len do 
		rv = dict.nes("NES_CPU_RD", base+i)
		io.write(string.format("%X.", rv))
		i = i+1
	end

	print("")
end

local function write_gift(base, off)

	local i
	local rv
	init_mapper()

	--select last bank in flash mode
	dict.nes("NES_CPU_WR", 0x5000, 0x81)
	dict.nes("NES_CPU_WR", 0x8000, 0xFF)
	dict.nes("NES_CPU_WR", 0x5000, 0x54)

	--enter unlock bypass mode
	dict.nes("FLASH_3V_WR", 0x8AAA, 0xAA)
	dict.nes("FLASH_3V_WR", 0x8555, 0x55)
	dict.nes("FLASH_3V_WR", 0x8AAA, 0x20)

	--write 0xA0 to address of byte to write, then write data
	dict.nes("FLASH_3V_WR", base+off, 0xA0)
	dict.nes("FLASH_3V_WR", base+off, 0x00)		--end previous line
	off=off+1
	dict.nes("FLASH_3V_WR", base+off, 0xA0)
	dict.nes("FLASH_3V_WR", base+off, 0x15)		--line number..?
	off=off+1
	dict.nes("FLASH_3V_WR", base+off, 0xA0)
	dict.nes("FLASH_3V_WR", base+off, string.byte("(",1))		--start with open parenth


	--off = off + 1	--increase to start of message but index starting at 1
	i = 1

	--regular editions don't have gift messages
	--local msg1 = "Contributor Edition"
	--local msg1 = "Limited Edition"
	--local msg2 = "82 of 100"	--  all flashed

	--local msg1 = " Contributor Edition "
	--local msg2 = " PinoBatch "	--issue if capital P or R is first char for some reason..

	local len = string.len(msg1)

	while (i <= len) do
		dict.nes("FLASH_3V_WR", base+off+i, 0xA0)
		dict.nes("FLASH_3V_WR", base+off+i, string.byte(msg1,i))	--line 1 of message
		print("write:", string.byte(msg1,i))
		i=i+1
	end

	off = off + i

	dict.nes("FLASH_3V_WR", base+off, 0xA0)
	dict.nes("FLASH_3V_WR", base+off, 0x00)		--end current line
	off=off+1
	dict.nes("FLASH_3V_WR", base+off, 0xA0)
	dict.nes("FLASH_3V_WR", base+off, 0x16)		--line number..?
	off=off+1
	dict.nes("FLASH_3V_WR", base+off, 0xA0)
	dict.nes("FLASH_3V_WR", base+off, string.byte("(",1))		--start with open parenth

	i = 1


	len = string.len(msg2)

	while (i <= len) do
		dict.nes("FLASH_3V_WR", base+off+i, 0xA0)
		dict.nes("FLASH_3V_WR", base+off+i, string.byte(msg2,i))	--line 2 of message
		print("write:", string.byte(msg2,i))
		i=i+1
	end

	off = off + i

	dict.nes("FLASH_3V_WR", base+off, 0xA0)
	dict.nes("FLASH_3V_WR", base+off, 0x00)		--end current line

	--]]


	--poll until stops toggling, or data is as wrote
--	rv = dict.nes("NES_CPU_RD", 0x8BDC)
--	print (rv)


	--exit unlock bypass
	dict.nes("FLASH_3V_WR", 0x8000, 0x90)
	dict.nes("FLASH_3V_WR", 0x8000, 0x00)
	--reset the flash chip
	dict.nes("FLASH_3V_WR", 0x8000, 0xF0)

end


--Cart should be in reset state upon calling this function 
--this function processes all user requests for this specific board/mapper
local function process(process_opts, console_opts)
	local test = process_opts["test"]
	local read = process_opts["read"]
	local erase = process_opts["erase"]
	local program = process_opts["program"]
	local verify = process_opts["verify"]
	local dumpfile = process_opts["dump_filename"]
	local flashfile = process_opts["flash_filename"]
	local verifyfile = process_opts["verify_filename"]

	local rv = nil
	local file 
	local prg_size = console_opts["prg_rom_size_kb"]
	local chr_size = console_opts["chr_rom_size_kb"]
	local wram_size = console_opts["wram_size_kb"]

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

--test cart by reading manf/prod ID
	if test then
		prgrom_manf_id(true)

		--manipulate gift message
		local base = 0x8BD0
		local start_offset = 0xC
		local len = 80
		--read_gift(base, len)

		--write_gift(base, start_offset)

		read_gift(base, len)
	end

--dump the cart to dumpfile
	if read then
		print("\nDumping PRG & CHR ROMs...")

		--initialize the mapper for dumping
		init_mapper(debug)

		file = assert(io.open(dumpfile, "wb"))

		--create header: pass open & empty file & rom sizes
		create_header(file, prg_size, chr_size)

		--dump cart into file
		dump_prgrom(file, prg_size, false)

		--close file
		assert(file:close())

		print("DONE Dumping PRG & CHR ROMs")
	end

--erase the cart
--	erase = nil
	if erase then

		--initialize the mapper for erasing
		init_mapper(debug)

		print("\nerasing action53 tsop takes ~30sec");

		print("erasing PRG-ROM");
		--A0-A14 are all directly addressable in CNROM mode
		--only A0-A11 are required to be valid for tsop-48
		--and mapper writes don't affect PRG banking
		dict.nes("FLASH_3V_WR", 0x8AAA, 0xAA)
		dict.nes("FLASH_3V_WR", 0x8555, 0x55)
		dict.nes("FLASH_3V_WR", 0x8AAA, 0x80)
		dict.nes("FLASH_3V_WR", 0x8AAA, 0xAA)
		dict.nes("FLASH_3V_WR", 0x8555, 0x55)
		dict.nes("FLASH_3V_WR", 0x8AAA, 0x10)
		rv = dict.nes("NES_CPU_RD", 0x8000)

		local i = 0

		--TODO create some function to pass the read value 
		--that's smart enough to figure out if the board is actually erasing or not
		while ( rv ~= 0xFF ) do
			rv = dict.nes("NES_CPU_RD", 0x8000)
			i = i + 1
		end
		print(i, "naks, done erasing prg.");

	end


--program flashfile to the cart
	if program then

		--initialize the mapper for dumping
		init_mapper(debug)

		--open file
		file = assert(io.open(flashfile, "rb"))
		--determine if auto-doubling, deinterleaving, etc, 
		--needs done to make board compatible with rom

		--not susceptible to bus conflicts

		--flash cart
		flash_prgrom(file, prg_size, true)

		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually

		--initialize the mapper for dumping
		init_mapper(debug)

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		dump_prgrom(file, prg_size, false)

		--close file
		assert(file:close())

		--compare the flash file vs post dump file
		if (files.compare( verifyfile, flashfile, true ) ) then
			print("\nSUCCESS! Flash verified")
		else
			print("\n\n\n FAILURE! Flash verification did not match")
		end
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
action53_tsop.process = process

-- return the module's table
return action53_tsop
