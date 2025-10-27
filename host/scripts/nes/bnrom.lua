
-- create the module's table
local bnrom = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local time = require "scripts.app.time"
local files = require "scripts.app.files"
local swim = require "scripts.app.swim"
local buffers = require "scripts.app.buffers"

-- file constants & variables
local mapname = "BxROM"
local banktable_base = 0xFF94 --Lizard
--local banktable_base = 0xFFE0 --HH85
--local rom_FF_addr = 0x8000

-- local functions
local function create_header( file, prgKB, chrKB )

	local mirroring = nes.detect_mapper_mirroring()

	--write_header( file, prgKB, chrKB, mapper, mirroring )
	nes.write_header( file, prgKB, 0, op_buffer[mapname], mirroring)
end

local function dump_cic_message( debug ) 

	--test reading back CIC version
	dict.io("SWIM_INIT", "SWIM_ON_A0")	
	--dict.io("SWIM_INIT", "SWIM_ON_EXP0")	
	if swim.start() then
		swim.read_stack()
	else
		print("ERROR trying to read back CIC signature stack data")
	end
	swim.stop_and_reset()


	dict.io("IO_RESET")	
	dict.io("NES_INIT")	

end


--read PRG-ROM flash ID
local function prgrom_manf_id( debug )

	--init_mapper()

	if debug then print("reading PRG-ROM manf ID") end

	--enter software mode
	--ROMSEL controls PRG-ROM /OE which needs to be low for flash writes
	--So unlock commands need to be addressed below $8000
	--DISCRETE_EXP0_PRGROM_WR doesn't toggle /ROMSEL by definition though, so A15 is unused
	--	    15 14 13 12
	-- 0x5 = 0b  0  1  0  1	-> $5555
	-- 0x2 = 0b  0  0  1  0	-> $2AAA
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x90)

	--read manf ID
	local rv = dict.nes("NES_CPU_RD", 0x8000)
	if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end

	--read prod ID
	rv = dict.nes("NES_CPU_RD", 0x8001)
	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end

	--exit software
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x8000, 0xF0)

end



--writes a byte to the currently selected bank
local function wr_prg_flash_byte(addr, value, debug)

	--same as NROM, but desired bank must already be selected
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xA0)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", addr, value)

	local rv = dict.nes("NES_CPU_RD", addr)

	local i = 0

	while ( rv ~= value ) do
		rv = dict.nes("NES_CPU_RD", addr)
		i = i + 1
	end
	if debug then print(i, "naks, done writing byte.") end
end

--base is the actual NES CPU address, not the rom offset (ie $FFF0, not $7FF0)
local function wr_bank_table(base, entries)

	--BNROM needs to have a bank table present in each and every bank
	--it should also be at the same location in every bank

--	--first select the last bank as cartridge should be erased (all 0xFF)
--	--go ahead and write the value to where it's supposed to be incase rom isn't erased
--	dict.nes("NES_CPU_WR", base+entries-1, entries-1)
--
--	--write bank table to selected bank
--	while( i < entries) do
--		wr_prg_flash_byte(base+i, i)
--		i = i+1;
--	end
--	--now we can use that bank table to jump to any other bank
	
	--smarter solution is to simply count down so we can use just one loop

	local cur_bank = entries - 1  --16 minus 1 is 15 = 0x0F

	while( cur_bank >= 0 ) do
		--select bank to write to (last bank first)
		--use the bank table to make the switch
		dict.nes("NES_CPU_WR", base+cur_bank, cur_bank)

		--write bank table to selected bank
		local i = 0
		while( i < entries) do
			wr_prg_flash_byte(base+i, i)
			i = i+1;
		end

		cur_bank = cur_bank-1
	end

end


--dump the PRG ROM
local function dump_prgrom( file, rom_size_KB, debug )

	local KB_per_read = 32
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x08	-- $8000

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		--select desired bank(s) to dump
		dict.nes("NES_CPU_WR", banktable_base+read_count, read_count)	--32KB @ CPU $8000

		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_4KB", false )

		read_count = read_count + 1
	end

end


--this is controlled from the host side one bank at a time
--but requires mapper specific firmware flashing functions
local function flash_prgrom(file, rom_size_KB, debug)

	--init_mapper()
	
	--bank table should already be written
	
	--test some bytes
	--wr_prg_flash_byte(0x0000, 0xA5, true)
	--wr_prg_flash_byte(0xFFFF, 0x5A, true)

	print("\nProgramming PRG-ROM flash")

	local base_addr = 0x8000 --writes occur $8000-9FFF
	local bank_size = 32*1024 --BNROM 32KByte per PRG bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata

	while cur_bank < total_banks do

		if (cur_bank %4 == 0) then
			print("writting PRG bank: ", cur_bank, " of ", total_banks-1)
		end

		--write the current bank to the mapper register
		dict.nes("NES_CPU_WR", banktable_base+cur_bank, cur_bank)

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
			--can use same write function as NROM
			dict.nes("NROM_PRG_FLASH_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)

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
		--Same as NROM
		flash.write_file( file, bank_size/1024, "NROM", "PRGROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")

end


--Cart should be in reset state upon calling this function 
--this function processes all user requests for this specific board/mapper
--local function process( test, read, erase, program, verify, dumpfile, flashfile, verifyfile)
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
		print("Testing ", mapname)

		nes.detect_mapper_mirroring(true)
		nes.ppu_ram_sense(0x1000, true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	

		prgrom_manf_id(true)
		--dump_cic_message(  ) 

	--
	end

--dump the cart to dumpfile
	if read then
		print("\nDumping PRG-ROM...")
		file = assert(io.open(dumpfile, "wb"))

		--create header: pass open & empty file & rom sizes
		create_header(file, prg_size, chr_size)

		--TODO find bank table to avoid bus conflicts!
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

		print("\nErasing", mapname);

		print("erasing PRG-ROM");
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x80)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x10)
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
		--open file
		file = assert(io.open(flashfile, "rb"))
		--determine if auto-doubling, deinterleaving, etc, 
		--needs done to make board compatible with rom

		time.start()

		--write bank table to all banks of cartridge
		wr_bank_table(banktable_base, prg_size/32) --32KB per bank
		--TODO need to verify where bank table belongs and properly determine number of banks

		--flash cart
		flash_prgrom(file, prg_size, true)

		time.report(prg_size)

		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually
		print("\nPost dumping PRG-ROM")

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		time.start()
		dump_prgrom(file, prg_size, false)
		time.report(prg_size)

		--close file
		assert(file:close())

		print("DONE post dumping PRG-ROM")

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
bnrom.process = process

-- return the module's table
return bnrom
