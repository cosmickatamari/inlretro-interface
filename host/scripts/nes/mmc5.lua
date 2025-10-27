
-- create the module's table
local mmc5 = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local buffers = require "scripts.app.buffers"
local help = require "scripts.app.help"

-- file constants
local mapname = "MMC5"

-- local functions

local function create_header( file, prgKB, chrKB )

	--write_header( file, prgKB, chrKB, mapper, mirroring )
	nes.write_header( file, prgKB, chrKB, op_buffer[mapname], 0)
end


--disables WRAM, selects Vertical mirroring
local function init_mapper( debug )


	--for save data safety start by disabling WRAM writes
	dict.nes("NES_CPU_WR", 0x5102, 0x01)	--bits 1&0 must be '01' (ie 0x02) to allow writes to WRAM
	dict.nes("NES_CPU_WR", 0x5103, 0x02)	--bits 1&0 must be '10' (ie 0x01) to allow writes to WRAM
	
	--set mirroring
	dict.nes("NES_CPU_WR", 0x5105, 0x44)	--vertical mirroring

	--PRG MODE
--	dict.nes("NES_CPU_WR", 0x5100, 0x00)	--PRGbanking mode0 single 32KByte bank (couldn't get this to work..)
	dict.nes("NES_CPU_WR", 0x5100, 0x03)	--PRGbanking mode3 4x 8KB banks

	--CHR MODE
	dict.nes("NES_CPU_WR", 0x5101, 0x00)	--single 8KByte bank

	--PRG-RAM bank
	dict.nes("NES_CPU_WR", 0x5113, 0x00)	--PRG-RAM bank @ $6000-7FFF (regardless of PRG mode)

	--PRG-ROM bank
--	dict.nes("NES_CPU_WR", 0x5117, 0x00)	--PRG-ROM bank @ $8000-FFFF (mode0) bits 1&0 don't matter (CPU A14/13)
	dict.nes("NES_CPU_WR", 0x5114, 0x80)	--PRG-ROM bank @ $8000-9FFF (mode3) bit7 must be set to see ROM
	dict.nes("NES_CPU_WR", 0x5115, 0x81)	--PRG-ROM bank @ $A000-BFFF (mode3) bit7 must be set to see ROM
	dict.nes("NES_CPU_WR", 0x5116, 0x82)	--PRG-ROM bank @ $C000-DFFF (mode3) bit7 must be set to see ROM
	dict.nes("NES_CPU_WR", 0x5117, 0x83)	--PRG-ROM bank @ $E000-FFFF (mode3) bit7 must be set to see ROM

	--CHR-ROM bank
	dict.nes("NES_CPU_WR", 0x5127, 0x00)	--CHR-ROM bank @ $0000-1FFF (mode0)
	dict.nes("NES_CPU_WR", 0x512B, 0x00)	--CHR-ROM bank @ $0000-1FFF (mode0 8x16 sprites)

	--CHR-ROM upper bank
	--TODO
	--dict.nes("NES_CPU_WR", 0x5130, 0x00)

end


--test the mapper's mirroring modes to verify working properly
--can be used to help identify board: returns true if pass, false if failed
local function mirror_test( debug )

	--put mapper in known state (mirror bits cleared)
	init_mapper() 

	--$5015 = 0x44: Vertical
	dict.nes("NES_CPU_WR", 0x5105, 0x44)
	if (nes.detect_mapper_mirroring(true) ~= "VERT") then
		print(mapname, " vert mirror test fail")
		return false
	end

	--$5015 = 0x50: Horizontal
	dict.nes("NES_CPU_WR", 0x5105, 0x50)
	if (nes.detect_mapper_mirroring(true) ~= "HORZ") then
		print(mapname, " horz mirror test fail")
		return false
	end

	--$5015 = 0x00: single screen 0
	dict.nes("NES_CPU_WR", 0x5105, 0x00)
	if (nes.detect_mapper_mirroring() ~= "1SCNA") then
		print("MMC1 mirror test fail (1 screen A)")
		return false
	end

	--$5015 = 0x55: single screen 1
	dict.nes("NES_CPU_WR", 0x5105, 0x55)
	if (nes.detect_mapper_mirroring() ~= "1SCNB") then
		print("MMC1 mirror test fail (1 screen B)")
		return false
	end

	--TODO fancy MMC5 other mirroring options (EXRAM etc)

	--passed all tests
	if(debug) then print(mapname, " mirror test passed") end
	return true
end


--dump the PRG ROM
local function dump_prgrom( file, rom_size_KB, debug )

	--PRG-ROM dump 32KB at a time through $5117 in mode 0
	--local KB_per_read = 32
	--above didn't work, dump 8KB at at time through $5114 in mode 3
	local KB_per_read = 8
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x80	-- $8000 PAGE

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		--select desired bank(s) to dump
		--dict.nes("NES_CPU_WR", 0x5117, ((read_count<<2)|0x80))	--32KB & CPU $8000 (bits0&1 don't matter)
		--above didn't work, only saw the last 8KB repeated...
		dict.nes("NES_CPU_WR", 0x5114, (read_count|0x80))	--8KB & CPU $8000 (bit7 must be set to see ROM)

		--dump bank's worth of data
		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_PAGE", false )

		read_count = read_count + 1
	end

end 
--dump the CHR ROM
local function dump_chrrom( file, rom_size_KB, debug )

	local KB_per_read = 8	--dump 8KB at a time
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00	-- $0000

	while ( read_count < num_reads ) do

		if debug then print( "dump CHR part ", read_count, " of ", num_reads) end

		--CHR-ROM bank
		dict.nes("NES_CPU_WR", 0x5127, read_count)	--CHR-ROM bank @ $0000-1FFF (mode0)
		dict.nes("NES_CPU_WR", 0x512B, read_count)	--CHR-ROM bank @ $0000-1FFF (mode0 8x16 sprites)

		dump.dumptofile( file, KB_per_read, addr_base, "NESPPU_PAGE", false )

		read_count = read_count + 1
	end

end


--dump the WRAM, assumes the WRAM was enabled/disabled as desired prior to calling
local function dump_wram( file, rom_size_KB, debug )

	local KB_per_read = 8
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	--local addr_base = 0x60	-- $6000
	local addr_base = 0x06	-- lower nibble for 4KB

	--debugging reads
--	local rv = dict.nes("NES_CPU_RD", 0x600B)
--	print("600B:", help.hex(rv))
--	rv = dict.nes("NES_CPU_RD", 0x600C)
--	print("600C:", help.hex(rv))
--	rv = dict.nes("NES_CPU_RD", 0x600D)
--	print("600D:", help.hex(rv))

	---[[
	while ( read_count < num_reads ) do

		--select the RAM bank with $5113 register
		dict.nes("NES_CPU_WR", 0x5113, read_count)	--PRG-RAM bank @ $6000-7FFF (regardless of PRG mode)

		if debug then print( "dump WRAM part ", read_count, " of ", num_reads) end

		--dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_PAGE", false )
		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_4KB_TOGGLE", false )

		read_count = read_count + 1
	end
		--]]

	--[[
	--read 1 Byte at a time from the host side
	local rv
	local addr = 0x6000
	while ( addr < 0x8000 ) do
		rv = dict.nes("NES_CPU_RD", addr)
	--	print(help.hex(addr), help.hex(rv))
--		file:write(string.char( rv ))
		help.file_wr_bin(file, rv)
		addr = addr+1
	end
	]]--

end


--write to the WRAM, assumes the WRAM was enabled/disabled as desired prior to calling
local function write_ram(file, ram_size_KB, debug)

--	init_mapper()

	--test some bytes
	--wr_prg_flash_byte(0x0000, 0xA5, true)
	--wr_prg_flash_byte(0x0FFF, 0x5A, true)

	print("\nProgramming PRG-RAM")
	--initial testing of MMC3 with no specific MMC3 flash firmware functions 6min per 256KByte = 0.7KBps


	local base_addr = 0x6000 --writes occur $6000-7FFF
	local bank_size = 8*1024 --MMC5 8KByte per RAM bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = ram_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata
	local rv
	local timout


	while cur_bank < total_banks do

		if (cur_bank %8 == 0) then
			print("writting RAM bank: ", cur_bank, " of ", total_banks-1)
		end

		--write the current bank to the mapper register
		--DATA writes written to $6000-7FFF
		dict.nes("NES_CPU_WR", 0x5113, cur_bank)	--PRG-RAM bank @ $6000-7FFF (regardless of PRG mode)


		--program the entire bank's worth of data

		---[[  This version of the code programs a single byte at a time but doesn't require 
		--	MMC3 specific functions in the firmware
		--print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware MMC3 specific functions 100% host flash algo:
			--wr_prg_flash_byte(base_addr+byte_num, data, false)   --0.7KBps

			--need to quickly write the byte after unlocking the PRG-RAM
			--before the 11.2usec timeout happens
			rv = dict.nes("MMC5_PRG_RAM_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)

			if (rv == data) then
				--write succeeded
				timeout = 0
			else
				print("PRG-RAM byte failed to write, retrying")
				rv = dict.nes("MMC5_PRG_RAM_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)
				if (rv ~= data) then
					print("FAILED on RETRY...")
				end
			end

			byte_num = byte_num + 1
		end
		--]]

		--Have the device write a banks worth of data
		--FAST!  13sec for 512KB = 39KBps
		--flash.write_file( file, bank_size/1024, mapname, "PRGROM", false )
		--flash.write_file( file, bank_size/1024, "NOVAR", "PRGRAM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-RAM")

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
	local dumpram = process_opts["dumpram"]
	local ramdumpfile = process_opts["dumpram_filename"]
	local writeram = process_opts["writeram"]
	local ramwritefile = process_opts["writeram_filename"]

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

		--verify mirroring is behaving as expected
		mirror_test(true)

		nes.ppu_ram_sense(0x1000, true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	

		--attempt to read PRG-ROM flash ID
	--	prgrom_manf_id(true)
	--	--attempt to read CHR-ROM flash ID
	--	chrrom_manf_id(true)
	end

--dump the ram to file 
	if dumpram then
		print("\nDumping WRAM...")

		init_mapper()
		
		file = assert(io.open(ramdumpfile, "wb"))

		--dump cart into file
		dump_wram(file, wram_size, false)

		--close file
		assert(file:close())

		print("DONE Dumping WRAM")
	end



--dump the cart to dumpfile
	if read then
		print("\nDumping PRG & CHR ROMs...")

		init_mapper()

		file = assert(io.open(dumpfile, "wb"))

		--create header: pass open & empty file & rom sizes
		create_header(file, prg_size, chr_size)

		--dump cart into file
		dump_prgrom(file, prg_size, false)
		dump_chrrom(file, chr_size, false)

		--close file
		assert(file:close())

		print("DONE Dumping PRG & CHR ROMs")
	end


--erase the cart
	if erase then

		print("\nerasing ", mapname, "not supported")


	end

--write to wram on the cart
	if writeram then

		print("\nWritting to WRAM...")

		init_mapper()
		
		--disable write protection, and enable WRAM
		--for save data safety start by disabling WRAM writes
	--	dict.nes("NES_CPU_WR", 0x5102, 0x02)	--bits 1&0 must be '01' (ie 0x02) to allow writes to WRAM
	--	dict.nes("NES_CPU_WR", 0x5103, 0x01)	--bits 1&0 must be '10' (ie 0x01) to allow writes to WRAM

		--test with 1 Byte
--		local addr = 0x600C
--		local rv = dict.nes("NES_CPU_RD", addr)
--		print(help.hex(addr), ":", help.hex(rv))
--		dict.nes("NES_CPU_WR", addr, 0xAA)
--		rv = dict.nes("NES_CPU_RD", addr)
--		print(help.hex(addr), ":", help.hex(rv))

--	rv = dict.nes("NES_CPU_RD", 0x600C)
--	print("600C:", help.hex(rv))
--	rv = dict.nes("NES_CPU_RD", 0x600D)
--	print("600D:", help.hex(rv))

		file = assert(io.open(ramwritefile, "rb"))

		write_ram(file, wram_size, true)
		--flash.write_file( file, wram_size, "NOVAR", "PRGRAM", false )
		--flash.write_file( file, wram_size, "MMC5", "PRGRAM", false )

		--for save data safety disable WRAM writes
	--	dict.nes("NES_CPU_WR", 0x5102, 0x01)	--bits 1&0 must be '01' (ie 0x02) to allow writes to WRAM
	--	dict.nes("NES_CPU_WR", 0x5103, 0x02)	--bits 1&0 must be '10' (ie 0x01) to allow writes to WRAM

		--close file
		assert(file:close())

		print("DONE Writting WRAM")
	end

--program flashfile to the cart
	if program then

		print("\nflashing ", mapname, "not supported")

	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually
		print("\nPost dumping PRG & CHR ROMs...")

		init_mapper()

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		dump_prgrom(file, prg_size, false)
		dump_chrrom(file, chr_size, false)

		--close file
		assert(file:close())

		print("DONE post dumping PRG & CHR ROMs")
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
mmc5.process = process

-- return the module's table
return mmc5
