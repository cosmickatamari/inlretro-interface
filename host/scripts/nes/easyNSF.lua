
-- create the module's table
local easyNSF = {}

-- import required modules
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local buffers = require "scripts.app.buffers"
local nes = require "scripts.app.nes"
local files = require "scripts.app.files"
local time = require "scripts.app.time"

-- file constants
local mapname = "EZNSF"


-- local functions

local function create_header( file, prgKB, chrKB )

	local mirroring = nes.detect_mapper_mirroring()

	--write_header( file, prgKB, chrKB, mapper, mirroring )
	nes.write_header( file, prgKB, 0, op_buffer[mapname], mirroring)
end


--local function wr_flash_byte(addr, value, debug)

--base is the actual NES CPU address, not the rom offset (ie $FFF0, not $7FF0)
--local function wr_bank_table(base, entries)
--Action53 not susceptible to bus conflicts, no banktable needed



--initialize mapper for dump/flash routines
local function init_mapper( debug )

	--rom A11-0 are directly connected to CPU
	--A12 pin is part of sector address
	--in BYTE mode, pin A12 is actually CPU A13
	--so ROM A11 must be valid for flash commands
	--ROM A11 pin is actually CPU A12
	--A12 is actually controlled my mapper register...
	--So it should need to be initialized to work, but flash ID is responding properly without it..
	--Therefore I don't think rom A11 pin (CPU A12) needs to be valid, just A11-0?
	

	dict.nes("NES_CPU_WR", 0x5000, 0x00)
	dict.nes("NES_CPU_WR", 0x5001, 0x00)
	dict.nes("NES_CPU_WR", 0x5002, 0x00)
	dict.nes("NES_CPU_WR", 0x5003, 0x00)
	dict.nes("NES_CPU_WR", 0x5004, 0x00)
	dict.nes("NES_CPU_WR", 0x5005, 0x00)
	dict.nes("NES_CPU_WR", 0x5006, 0x00)
	dict.nes("NES_CPU_WR", 0x5007, 0x00)

	--flash /WE signal only goes low for $9000-9FFF

end


--read PRG-ROM flash ID
local function prgrom_manf_id( debug )

	local rv
	init_mapper()

	if debug then print("reading PRG-ROM manf ID") end
	--A0-A14 are all directly addressable in CNROM mode
	--and mapper writes don't affect PRG banking
	dict.nes("FLASH_3V_WR", 0x9AAA, 0xAA)
	dict.nes("FLASH_3V_WR", 0x9555, 0x55)
	dict.nes("FLASH_3V_WR", 0x9AAA, 0x90)
	rv = dict.nes("NES_CPU_RD", 0x8000)
	if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end	--0x01
	rv = dict.nes("NES_CPU_RD", 0x8002)
	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end	--0xDA(top), 0x5B(bot)

	--exit software
	dict.nes("FLASH_3V_WR", 0x9000, 0xF0)

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


	local base_addr = 0x9000 --writes occur $9000-9FFF
	local bank_size = 4*1024 --4KB PRG bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata


	while cur_bank < total_banks do

		if (cur_bank %32 == 0) then
			print("writting PRG bank: ", cur_bank, " of ", total_banks-1)
		end

		--write the current bank to the mapper register
		dict.nes("NES_CPU_WR", 0x5001, cur_bank) --bank at $9000


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

	local KB_per_read = 4
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x80	-- $8000

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		--select desired bank(s) to dump
		--mapper 30 bank register is $C000-FFFF
		dict.nes("NES_CPU_WR", 0x5000, read_count)	--16KB @ CPU $8000

		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_PAGE", false )

		read_count = read_count + 1
	end

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
	local mirror = console_opts["mirror"]

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

--test cart by reading manf/prod ID
	if test then
		prgrom_manf_id(true)

	end

--dump the cart to dumpfile
	if read then
		print("\nDumping PRG-ROM...")

		--initialize the mapper for dumping
		init_mapper(debug)

		file = assert(io.open(dumpfile, "wb"))

		--create header: pass open & empty file & rom sizes
		create_header(file, prg_size, chr_size)

		--dump cart into file
		time.start()
		dump_prgrom(file, prg_size, false)
		time.report(prg_size)

		--close file
		assert(file:close())
		print("DONE Dumping PRG-ROM")
	end

--erase the cart
	if erase then

		--initialize the mapper for erasing
		init_mapper(debug)

		print("\nerasing tsop takes ~30sec");

		print("erasing PRG-ROM");
		--A0-A14 are all directly addressable in CNROM mode
		--only A0-A11 are required to be valid for tsop-48
		--and mapper writes don't affect PRG banking
		dict.nes("FLASH_3V_WR", 0x9AAA, 0xAA)
		dict.nes("FLASH_3V_WR", 0x9555, 0x55)
		dict.nes("FLASH_3V_WR", 0x9AAA, 0x80)
		dict.nes("FLASH_3V_WR", 0x9AAA, 0xAA)
		dict.nes("FLASH_3V_WR", 0x9555, 0x55)
		dict.nes("FLASH_3V_WR", 0x9AAA, 0x10)
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
		--flash.write_file( file, 1024, "EZNSF", "PRGROM", true )
		time.start()
		flash_prgrom(file, prg_size, true)
		time.report(prg_size)
		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually
		print("\nVerifing PRG-ROM...")

		--initialize the mapper for dumping
		init_mapper(debug)

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		time.start()
		--dump.dumptofile( file, 1024, "EZNSF", "PRGROM", true )
		dump_prgrom(file, prg_size, false)
		time.report(prg_size)

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
easyNSF.process = process

-- return the module's table
return easyNSF
