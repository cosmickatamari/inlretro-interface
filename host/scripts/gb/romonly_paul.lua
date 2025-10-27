
-- create the module's table
local romonly = {}

-- import required modules
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local files = require "scripts.app.files"

-- file constants
local mapname = "ROMONLY"

-- local functions

--read PRG-ROM flash ID
local function rom_manf_id( debug )

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

	--verify exited
--	rv = dict.nes("NES_CPU_RD", 0x8001)
--	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end
	
end



--dump the ROM
local function dump_rom( file, rom_size_KB, debug )

	--ROM ONLY dump all 32KB, most of this code is overkill for no MBC.
	--	but follows same format as MBC's
	local KB_per_read = 32	--$0000-7FFF is ROM space (32KByte)
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00	-- $0000 base address for ROM

	while ( read_count < num_reads ) do

		if debug then print( "dump ROM part ", read_count, " of ", num_reads) end

		dump.dumptofile( file, KB_per_read, addr_base, "GAMEBOY_PAGE", false )

		read_count = read_count + 1
	end

end

--write a single byte to ROM flash
local function wr_flash_byte(addr, value, debug)

	if (addr < 0x8000 or addr > 0xFFFF) then
		print("\n  ERROR! flash write to PRG-ROM", string.format("$%X", addr), "must be $8000-FFFF \n\n")
		return
	end

	--send unlock command and write byte
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

	--TODO handle timeout for problems

	--TODO return pass/fail/info
end



--fast host flash one bank at a time...
--this is controlled from the host side one bank at a time
--but requires specific firmware MMC3 flashing functions
--there is super slow version commented out that doesn't require MMC3 specific firmware code
local function flash_rom(file, rom_size_KB, debug)

	--init_mapper()

	--test some bytes
	--wr_flash_byte(0x8000, 0xA5, true)
	--wr_flash_byte(0xFFFF, 0x5A, true)
	

	print("\nProgramming PRG-ROM flash")

	--most of this is overkill for NROM, but it's how we want to handle things for bigger mappers
	local base_addr = 0x8000 --writes occur $8000-9FFF
	local bank_size = 32*1024 --MMC3 8KByte per PRG bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata

	while cur_bank < total_banks do

		if (cur_bank %8 == 0) then
			print("writting PRG bank: ", cur_bank, " of ", total_banks-1)
		end

		--program the entire bank's worth of data
		flash.write_file( file, 32, mapname, "PRGROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")

end




--Cart should be in reset state upon calling this function 
--this function processes all user requests for this specific board/mapper
--local function process( test, read, erase, program, verify, dumpfile, flashfile, verifyfile, mirror)
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
	local rom_size = 32
	local ram_size = 0

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("GAMEBOY_INIT")

	dict.io("GB_POWER_5V")	--gameboy carts prob run fine at 3v if want to be safe

--test the cart
	if test then
	--	print("Testing ", mapname)

	--	nes.detect_mapper_mirroring(true)
	--	print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	
	--	--nes.read_flashID_prgrom_exp0(true)
	--	rom_manf_id(true)
	--	--nes.read_flashID_chrrom_8K(true)
	--	chrrom_manf_id(true)
	end

--dump the cart to dumpfile
	if read then

		print("\nDumping ROM...")

		--init_mapper()
		
		file = assert(io.open(dumpfile, "wb"))

		--dump cart into file
		dump_rom(file, rom_size, false)

		--close file
		assert(file:close())
		print("DONE Dumping ROM")
	end


--erase the cart
	if erase then

--		print("\nErasing ", mapname);
--
--		--init_mapper()
--
--		print("erasing PRG-ROM");
--		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
--		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
--		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x80)
--		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
--		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
--		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x10)
--		rv = dict.nes("NES_CPU_RD", 0x8000)
--
--		local i = 0
--
--		--TODO create some function to pass the read value 
--		--that's smart enough to figure out if the board is actually erasing or not
--		while ( rv ~= 0xFF ) do
--			rv = dict.nes("NES_CPU_RD", 0x8000)
--			i = i + 1
--		end
--		print(i, "naks, done erasing prg.");
--
--		print("erasing CHR-ROM");
--		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
--		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
--		dict.nes("NES_PPU_WR", 0x1555, 0x80)
--		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
--		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
--		dict.nes("NES_PPU_WR", 0x1555, 0x10)
--		rv = dict.nes("NES_PPU_RD", 0x0000)
--
--		i = 0
--		while ( rv ~= 0xFF ) do
--			rv = dict.nes("NES_PPU_RD", 0x0000)
--			i = i + 1
--		end
--		print(i, "naks, done erasing chr.\n");
	end


--program flashfile to the cart
	if program then
--		--open file
--		file = assert(io.open(flashfile, "rb"))
--		--determine if auto-doubling, deinterleaving, etc, 
--		--needs done to make board compatible with rom
--		--flash cart
--		flash_rom(file, rom_size, true)
--		--close file
--		assert(file:close())
--
	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually
		print("\nPost dumping ROM...")

		--init_mapper()

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		dump_rom(file, rom_size, false)

		--close file
		assert(file:close())

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
romonly.process = process

-- return the module's table
return romonly
