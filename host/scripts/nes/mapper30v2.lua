
-- create the module's table
local mapper30v2 = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local time = require "scripts.app.time"
local files = require "scripts.app.files"
local ciccom = require "scripts.app.ciccom"
local swim = require "scripts.app.swim"
local mapper30_legacy = require "scripts.nes.mapper30"
local buffers = require "scripts.app.buffers"

-- file constants & variables
local mapname = "MAP30"

-- local functions

local function create_header( file, prgKB, chrKB )

	local mirroring = nes.detect_mapper_mirroring()

	--write_header( file, prgKB, chrKB, mapper, mirroring )
	nes.write_header( file, prgKB, 0, op_buffer[mapname], mirroring)
end


--read PRG-ROM flash ID
local function prgrom_manf_id( debug )


	if debug then print("reading PRG-ROM manf ID") end
	--no bus conflicts
	--$8000-BFFF writes to flash
	--$C000-FFFF writes to mapper
	--ROM A14 is mapper controlled
	--
	--A15 14 - 13 12
	-- 1   1    0  1  : 0x5555 -> bank1, $9555
	-- 1   0    1  0  : 0x2AAA -> bank0, $AAAA
	dict.nes("NES_CPU_WR", 0xC000, 0x01)
	dict.nes("NES_CPU_WR", 0x9555, 0xAA)

	dict.nes("NES_CPU_WR", 0xC000, 0x00)
	dict.nes("NES_CPU_WR", 0xAAAA, 0x55)

	dict.nes("NES_CPU_WR", 0xC000, 0x01)
	dict.nes("NES_CPU_WR", 0x9555, 0x90)

	rv = dict.nes("NES_CPU_RD", 0x8000)
	if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end
	rv = dict.nes("NES_CPU_RD", 0x8001)
	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end

	--exit software
	dict.nes("NES_CPU_WR", 0x8000, 0xF0)

end

--select different chr-ram banks and verify all 4 banks are present
local function map30_chrbank_test()

	dict.nes("NES_CPU_WR", 0xC000, 0x00) --CHR bank 0
	dict.nes("NES_PPU_WR", 0x0000, 0xAA)
	dict.nes("NES_CPU_WR", 0xC000, 0x20) --CHR bank 1
	dict.nes("NES_PPU_WR", 0x0000, 0x55)
	dict.nes("NES_CPU_WR", 0xC000, 0x40) --CHR bank 2
	dict.nes("NES_PPU_WR", 0x0000, 0xCC)
	dict.nes("NES_CPU_WR", 0xC000, 0x60) --CHR bank 3
	dict.nes("NES_PPU_WR", 0x0000, 0x33)

	--read back
	local test = true 
	dict.nes("NES_CPU_WR", 0xC000, 0x00) --CHR bank 0
	rv = dict.nes("NES_PPU_RD", 0x0000)
	if rv ~= 0xAA then 
		print( "\nFAIL CHR-RAM BANKING TEST!!!\n")
		print("bank0 read:", string.format("%X", rv))
		test = false
	end
	dict.nes("NES_CPU_WR", 0xC000, 0x20) --CHR bank 1
	rv = dict.nes("NES_PPU_RD", 0x0000)
	if rv ~= 0x55 then 
		print( "\nFAIL CHR-RAM BANKING TEST!!!\n")
		print("bank1 read:", string.format("%X", rv))
		test = false
	end
	dict.nes("NES_CPU_WR", 0xC000, 0x40) --CHR bank 2
	rv = dict.nes("NES_PPU_RD", 0x0000)
	if rv ~= 0xCC then 
		print( "\nFAIL CHR-RAM BANKING TEST!!!\n")
		print("bank2 read:", string.format("%X", rv))
		test = false
	end
	dict.nes("NES_CPU_WR", 0xC000, 0x60) --CHR bank 3
	rv = dict.nes("NES_PPU_RD", 0x0000)
	if rv ~= 0x33 then 
		print( "\nFAIL CHR-RAM BANKING TEST!!!\n")
		print("bank3 read:", string.format("%X", rv))
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

--dump the CHR ROM
local function dump_chrrom( file, rom_size_KB, debug )

	--CHR-ROM dump all 8KB, most of this code is overkill for NROM.
	--	but follows same format as banked mappers
	local KB_per_read = 8	
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00	-- $0000

	while ( read_count < num_reads ) do

		if debug then print( "dump CHR part ", read_count, " of ", num_reads) end

		dump.dumptofile( file, KB_per_read, addr_base, "NESPPU_PAGE", false )

		read_count = read_count + 1
	end

end


local function exercise_chrram(debug)
	
	if debug then print("exercising CHR-RAM") end
	dict.stuff("RESET_LFSR")	--sets it to 1
--	dict.stuff("SET_LFSR_L", 0) --lock it up to clear ram
--	dict.stuff("SET_LFSR_L", 2) --give different seed for testing fails


	--write random data to all 4 banks
	local bank = 0x00
	
	while (bank<=0x60) do
		--select the bank
		dict.nes("NES_CPU_WR", 0xC000, bank ) 
		bank = bank + 0x20

		local addr = 0x0000
		while (addr<0x2000) do
			dict.nes("PPU_PAGE_WR_LFSR", addr)
			addr = addr + 256
		end
	end

	local filename = "ignore/chrramdump.bin"

	local file = assert(io.open(filename, "wb"))

	bank = 0x00
	while (bank<=0x60) do
		--select the bank
		dict.nes("NES_CPU_WR", 0xC000, bank ) 
		bank = bank + 0x20

		dump_chrrom(file, 8)
	end

	--close the file
	assert(file:close())

	--re-open & compare dump with known lsfr bitstream
	local goodfile = "ignore/lfsr_32KB.bin"

	--compare the flash file vs post dump file
	if ( files.compare( filename, goodfile, true ) ) then
		print("CHR-RAM test verified")
		return true
	else
		print("FAILURE! CHR-RAM test failed")
		return false
	end


end

local function test_soft_mir_switch( debug ) 

	--set to Horiz
	if debug then print("test setting soft mir switch to Horiz") end
	ciccom.start()
	ciccom.set_opcode("M")
	--now send operand "V" (0x56) or "H" (0x48)
	ciccom.write("H")

	dict.io("IO_RESET")	
	time.sleep(0.05) --10msec to be overly safe

	--the CIC won't update the H/V stack flag unless it's reset
	--reset caused during swim init doesn't count either bc it halts at reset vector

	--test reading back CIC version
	dict.io("SWIM_INIT", "SWIM_ON_A0")	
	--dict.io("SWIM_INIT", "SWIM_ON_EXP0")	
	if swim.start() then
		swim.read_stack()
	else
		print("ERROR trying to read back CIC signature stack data")
	end
	swim.stop_and_reset()

	time.sleep(0.05) --10msec to be overly safe
	dict.io("NES_INIT")	
	if ( nes.detect_mapper_mirroring() == "HORZ" ) then
		if debug then print("pass Horiz soft mirror switch") end
	else
		print("\n\n\nFAIL HORZ SOFT MIRROR SWITCH TEST!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n\n")
		--don't continue
		return false
	end

	dict.io("IO_RESET")	
	

	--set to Vert
	ciccom.start()
	ciccom.set_opcode("M")
	--now send operand "V" (0x56) or "H" (0x48)
	ciccom.write("V")

	

	dict.io("IO_RESET")	
	time.sleep(0.05) --10msec to be overly safe


	--the CIC won't update the H/V stack flag unless it's reset
	--reset caused during swim init doesn't count either bc it halts at reset vector

	--test reading back CIC version
	dict.io("SWIM_INIT", "SWIM_ON_A0")	
	--dict.io("SWIM_INIT", "SWIM_ON_EXP0")	
	if swim.start() then

		swim.read_stack()

	else
		print("ERROR trying to read back CIC signature stack data")
	end
	swim.stop_and_reset()

	--print("done reading STM8 stack on A0\n")

	dict.io("NES_INIT")	
	if ( nes.detect_mapper_mirroring() == "VERT" ) then
		if debug then print("pass Vert soft mirror switch") end
	else
		print("\n\n\nFAIL VERT SOFT MIRROR SWITCH TEST!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n\n")
		--don't continue
		return false
	end

	dict.io("IO_RESET")	
	dict.io("NES_INIT")	

	print("Software mirroring switch operation verified working")
	return true
end

--dump the PRG ROM
local function dump_prgrom( file, rom_size_KB, debug )

	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x80	-- $8000

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		--select desired bank(s) to dump
		--mapper 30 bank register is $C000-FFFF
		dict.nes("NES_CPU_WR", 0xFC80, read_count)	--16KB @ CPU $8000

		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_PAGE", false )

		read_count = read_count + 1
	end

end


--REQ: addr must be in the first bank $8000-BFFF
local function wr_prg_flash_byte(addr, value, bank, debug)

	if (addr < 0x8000 or addr > 0xBFFF) then
		print("\n  ERROR! flash write to PRG-ROM", string.format("$%X", addr), "must be $8000-BFFF \n\n")
		return
	end

	dict.nes("NES_CPU_WR", 0xC000, 0x01) dict.nes("NES_CPU_WR", 0x9555, 0xAA)
	dict.nes("NES_CPU_WR", 0xC000, 0x00) dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
	dict.nes("NES_CPU_WR", 0xC000, 0x01) dict.nes("NES_CPU_WR", 0x9555, 0xA0)

	dict.nes("NES_CPU_WR", 0xC000, bank)
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

	print("\nProgramming PRG-ROM flash")

	local base_addr = 0x8000 --writes occur $8000-9FFF
	local bank_size = 16*1024 --UNROM 16KByte per PRG bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata

	--set the bank table address
	dict.nes("SET_BANK_TABLE", banktable_base) 
	if debug then print("get banktable:", string.format("%X", dict.nes("GET_BANK_TABLE"))) end

	while cur_bank < total_banks do

		if (cur_bank %4 == 0) then
			print("writting PRG bank: ", cur_bank, " of ", total_banks-1)
		end

		--select bank to flash
		dict.nes("SET_CUR_BANK", cur_bank) 
		if debug then print("get bank:", dict.nes("GET_CUR_BANK")) end

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
			--can use same write function as NROM
			dict.nes("MAP30_PRG_FLASH_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)

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
		flash.write_file( file, bank_size/1024, mapname, "PRGROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")

end

local function is_old_firmware( debug )

	if debug then print("checking for old firmware") end

	--check if CIRAM_A10_MIRRORING opcode is present
	--this was cut from later versions
	local rv
	rv = dict.nes("CIRAM_A10_MIRROR", nil, nil, nil, true)
	
	if debug then 
		if rv then print("old firmware sensed, running legacy mode")
		else print("later firmware sensed, running current script")
		end
	end

	return rv

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
	-- TODO: Cleanup needed here, support chrrom, make this look more like other mapper scripts.
	local prg_size = console_opts["prg_rom_size_kb"]
	local chr_size = console_opts["chr_rom_size_kb"]
	local wram_size = console_opts["wram_size_kb"]
	local mirror = console_opts["mirror"]

	--local filetype = "nes"
	local filetype = "bin"

	if is_old_firmware(true) then
		--call legacy mapper30 script
--local mapper30_legacy = require "scripts.nes.mapper30"
		mapper30_legacy.process(process_opts, console_opts)
		return
	end

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")


--test cart by reading manf/prod ID
	if test then
		print("Testing ", mapname)

		nes.detect_mapper_mirroring(true)
		nes.ppu_ram_sense(0x1000, true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	

		prgrom_manf_id( debug )

		--test CHR-RAM banking
		rv = map30_chrbank_test()
		--exit script if test fails
		if not rv then return end 

		--test CHR-RAM
		rv = exercise_chrram()
		--exit script if test fails
		if not rv then return end 

		--test software mirroring switch
		rv = test_soft_mir_switch()
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

		dict.nes("NES_CPU_WR", 0xC000, 0x01) dict.nes("NES_CPU_WR", 0x9555, 0xAA)
		dict.nes("NES_CPU_WR", 0xC000, 0x00) dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xC000, 0x01) dict.nes("NES_CPU_WR", 0x9555, 0x80)
		dict.nes("NES_CPU_WR", 0xC000, 0x01) dict.nes("NES_CPU_WR", 0x9555, 0xAA)
		dict.nes("NES_CPU_WR", 0xC000, 0x00) dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xC000, 0x01) dict.nes("NES_CPU_WR", 0x9555, 0x10)

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
		--TODO set mirroring bit via ciccom
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
mapper30v2.process = process

-- return the module's table
return mapper30v2
