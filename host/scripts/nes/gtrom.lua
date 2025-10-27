
-- create the module's table
local gtrom = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local time = require "scripts.app.time"
local files = require "scripts.app.files"
local time = require "scripts.app.time"
local buffers = require "scripts.app.buffers"

-- file constants & variables
local mapname = "GTROM"

-- local functions

local function create_header( file, prgKB, chrKB )

	--write_header( file, prgKB, chrKB, mapper, mirroring )
	nes.write_header( file, prgKB, chrKB, op_buffer[mapname], 0)
end


--read PRG-ROM flash ID
local function prgrom_manf_id( debug )


	if debug then print("reading PRG-ROM manf ID") end
	--no bus conflicts
	--$5000-5FFF / $7000-7FFF writes to mapper
	--$8000-FFFF writes to mapper
	--
	--A15 14 - 13 12
	-- 1   1    0  1  : 0x5555 -> $D555
	-- 1   0    1  0  : 0x2AAA -> $AAAA
	dict.nes("NES_CPU_WR", 0xD555, 0xAA)
	dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
	dict.nes("NES_CPU_WR", 0xD555, 0x90)

	rv = dict.nes("NES_CPU_RD", 0x8000)
	if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end
	rv = dict.nes("NES_CPU_RD", 0x8001)
	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end

	--exit software
	dict.nes("NES_CPU_WR", 0x8000, 0xF0)

end

--select different chr-ram banks and verify all 4 banks are present
local function gtrom_chrbank_test()

	dict.nes("NES_CPU_WR", 0x5000, 0x00) --PT & NT bank 0
	dict.nes("NES_PPU_WR", 0x0000, 0xAA) --PT write
	dict.nes("NES_PPU_WR", 0x2000, 0xCC) --NT write

	dict.nes("NES_CPU_WR", 0x5000, 0x30) --PT & NT bank 1
	dict.nes("NES_PPU_WR", 0x0000, 0x55) --PT write
	dict.nes("NES_PPU_WR", 0x2000, 0x33) --NT write

	--read back
	local test = true 
	dict.nes("NES_CPU_WR", 0x5000, 0x00) --CHR bank 0
	rv = dict.nes("NES_PPU_RD", 0x0000)
	if rv ~= 0xAA then 
		print( "\nFAIL CHR-RAM BANKING TEST!!!\n")
		print("PT bank0 read:", string.format("%X", rv))
		test = false
	end
	rv = dict.nes("NES_PPU_RD", 0x2000)
	if rv ~= 0xCC then 
		print( "\nFAIL CHR-RAM BANKING TEST!!!\n")
		print("NT bank0 read:", string.format("%X", rv))
		test = false
	end

	dict.nes("NES_CPU_WR", 0x5000, 0x30) --CHR bank 1
	rv = dict.nes("NES_PPU_RD", 0x0000)
	if rv ~= 0x55 then 
		print( "\nFAIL CHR-RAM BANKING TEST!!!\n")
		print("PT bank1 read:", string.format("%X", rv))
		test = false
	end
	rv = dict.nes("NES_PPU_RD", 0x2000)
	if rv ~= 0x33 then 
		print( "\nFAIL CHR-RAM BANKING TEST!!!\n")
		print("NT bank1 read:", string.format("%X", rv))
		test = false
	end

	if test then
		print("CHR-RAM BANKING TEST PASSED")
		return true
	else
		print("CHR-RAM BANKING TEST FAILED")
		return false
	end
end


--dump the PRG ROM
local function dump_prgrom( file, rom_size_KB, debug )

	local KB_per_read = 32
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x80	-- $8000

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		--select desired bank(s) to dump
		--mapper 30 bank register is $C000-FFFF
		dict.nes("NES_CPU_WR", 0x5000, read_count)	--32KB @ CPU $8000

		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_PAGE", false )

		read_count = read_count + 1
	end

end


--REQ: addr must be in the first bank $8000-BFFF
local function wr_prg_flash_byte(addr, value, bank, debug)

	if (addr < 0x8000 or addr > 0xFFFF) then
		print("\n  ERROR! flash write to PRG-ROM", string.format("$%X", addr), "must be $8000-FFFF \n\n")
		return
	end

	dict.nes("NES_CPU_WR", 0x5000, bank)

	dict.nes("NES_CPU_WR", 0xD555, 0xAA)
	dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
	dict.nes("NES_CPU_WR", 0xD555, 0xA0)

	dict.nes("NES_CPU_WR", addr, value)

	local rv = dict.nes("NES_CPU_RD", addr)

	local i = 0

	while ( rv ~= value ) do
		rv = dict.nes("NES_CPU_RD", addr)
		i = i + 1
	end
	if debug then print(i, "naks, done writing byte.") end

	--TODO report error if write failed
	
end


--this is controlled from the host side one bank at a time
--but requires mapper specific firmware flashing functions
local function flash_prgrom(file, rom_size_KB, debug)

	--init_mapper()
	
	--test some bytes
	--wr_prg_flash_byte(0x0000, 0xA5, 0, true)
	--wr_prg_flash_byte(0xFFFF, 0x5A, 1, true)
	--if true then return end

	print("\nProgramming PRG-ROM flash")

	local base_addr = 0x8000 --writes occur $8000-9FFF
	local bank_size = 32*1024 --UNROM 16KByte per PRG bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata

	while cur_bank < total_banks do

		if (cur_bank %4 == 0) then
			print("writting PRG bank: ", cur_bank, " of ", total_banks-1)
		end

		--select bank to flash
		dict.nes("NES_CPU_WR", 0x5000, cur_bank)
		dict.nes("SET_CUR_BANK", cur_bank) 

		--program the entire bank's worth of data

		--[[  This version of the code programs a single byte at a time but doesn't require 
		--	mapper specific functions in the firmware
		print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware MMC3 specific functions 100% host flash algo:
			--wr_prg_flash_byte(base_addr+byte_num, data, cur_bank, false)   --0.7KBps
			--EASIEST FIRMWARE SPEEDUP: 5x faster, create MMC3 write byte function:
			dict.nes("GTROM_PRG_FLASH_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)

			if (true) then
				readdata = dict.nes("NES_CPU_RD", base_addr+byte_num)
			--		print("flashed byte number", byte_num, " in bank",cur_bank, " to flash ", data, readdata)
				if readdata ~= data then
					print("ERROR flashing byte number", byte_num, " in bank",cur_bank, " to flash ", data, readdata)
				end
			end

			byte_num = byte_num + 1
		end
		--]]

		--Have the device write a banks worth of data
		flash.write_file( file, bank_size/1024, mapname, "PRGROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")

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

	--local filetype = "nes"
	local filetype = "bin"

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")


--test cart by reading manf/prod ID
	if test then
		print("Testing ", mapname)

		--nes.detect_mapper_mirroring(true)
		nes.ppu_ram_sense(0x1000, true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	

		prgrom_manf_id( debug )

		--test CHR-RAM banking
		rv = gtrom_chrbank_test()
		--exit script if test fails
		if not rv then return end 

	end

--dump the cart to dumpfile
	if read then
		print("\nDumping PRG-ROM...")
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


		print("\nerasing", mapname);

		dict.nes("NES_CPU_WR", 0xD555, 0xAA)
		dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xD555, 0x80)
		dict.nes("NES_CPU_WR", 0xD555, 0xAA)
		dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xD555, 0x10)

		local i = 0

		--TODO create some function to pass the read value 
		--that's smart enough to figure out if the board is actually erasing or not
		rv = 0xFF
		while ( rv ~= dict.nes("NES_CPU_RD", 0x8000)) do
			rv = dict.nes("NES_CPU_RD", 0x8000)
			i = i + 1
		end

		--TODO verify erase
		--for now we'll just report an error if naks isn't sizable
		--AVR is slower so naks are lower, tested was ~60
		if (i < 10) then
			print("ERROR flash did not appear to accept erase command, naks:", i)
			return
		else
			print(i, "naks, done erasing prg.");
		end

	end


--program flashfile to the cart
	if program then

		--open file
		file = assert(io.open(flashfile, "rb"))
		--determine if auto-doubling, deinterleaving, etc, 
		--needs done to make board compatible with rom
		

		if filetype == "nes" then
		--advance past the 16byte header
			local buffsize = 1
			local byte
			local count = 1

			for byte in file:lines(buffsize) do
				local data = string.unpack("B", byte, 1)
				--print(string.format("%X", data))
				count = count + 1
				if count == 17 then break end
			end
		end


		--flash cart
		time.start()
		flash_prgrom(file, prg_size, false)
		time.report(prg_size)

		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		time.start()
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

	return
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
gtrom.process = process

-- return the module's table
return gtrom
