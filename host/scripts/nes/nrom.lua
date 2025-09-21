
-- create the module's table
local nrom = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local swim = require "scripts.app.swim"
local ciccom = require "scripts.app.ciccom"
local buffers = require "scripts.app.buffers"

-- file constants
local mapname = "NROM"

-- local functions

local function create_header( file, prgKB, chrKB )

	local mirroring = nes.detect_mapper_mirroring()

	--write_header( file, prgKB, chrKB, mapper, mirroring )
	nes.write_header( file, prgKB, chrKB, dict.op_buffer[mapname], mirroring)
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

	--verify exited
--	rv = dict.nes("NES_CPU_RD", 0x8001)
--	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end
	
end


--read CHR-ROM flash ID
local function chrrom_manf_id( debug )

	--init_mapper()

	if debug then print("reading CHR-ROM manf ID") end

	--enter software mode
	--NROM has A13 tied to A11, and A14 tied to A12.
	--So only A0-12 needs to be valid
	--A13 needs to be low to address CHR-ROM
	--	    15 14 13 12
	-- 0x5 = 0b  0  1  0  1	-> $1555
	-- 0x2 = 0b  0  0  1  0	-> $0AAA
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
	dict.nes("NES_PPU_WR", 0x1555, 0x90)
	--read manf ID
	local rv = dict.nes("NES_PPU_RD", 0x0000)
	if debug then print("attempted read CHR-ROM manf ID:", string.format("%X", rv)) end

	--read prod ID
	rv = dict.nes("NES_PPU_RD", 0x0001)
	if debug then print("attempted read CHR-ROM prod ID:", string.format("%X", rv)) end

	--exit software
	dict.nes("NES_PPU_WR", 0x0000, 0xF0)

end


--dump the PRG ROM
local function dump_prgrom( file, rom_size_KB, debug )

	local KB_per_read = 32
	-- Handle 16KB nroms.
	if rom_size_KB < KB_per_read then KB_per_read = rom_size_KB end

	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x08	-- $8000

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_4KB", false )

		read_count = read_count + 1
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

		dump.dumptofile( file, KB_per_read, addr_base, "NESPPU_1KB", false )

		read_count = read_count + 1
	end

	--Zorchenhimer had issues dumping "Popeye no Eigo Asobi" http://bootgod.dyndns.org:7777/profile.php?id=3867
	--which appears to have 2 transistors with connections to PPU A12 and CHR-ROM /OE.?
	--not sure what's going on there, but slowly dumping one byte at at time instead of 128Byte read bursts
	--with normal dumping method above corrected the issue.
	--[[
	for i = 0x0000,0x1FFF,1 do
		val = dict.nes("NES_PPU_RD", i)
		file:write(string.char(val))
	end
        file:flush()
	--]]

end


--write a single byte to PRG-ROM flash
local function wr_prg_flash_byte(addr, value, debug)

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


--write a single byte to CHR-ROM flash
--PRE: assumes mapper is initialized and bank is selected as prescribed in mapper_init
--REQ: addr must be in the first 2 banks $0000-0FFF
local function wr_chr_flash_byte(addr, value, debug)

	if (addr < 0x0000 or addr > 0x1FFF) then
		print("\n  ERROR! flash write to CHR-ROM", string.format("$%X", addr), "must be $0000-1FFF \n\n")
		return
	end

	--send unlock command and write byte
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
	dict.nes("NES_PPU_WR", 0x1555, 0xA0)
	dict.nes("NES_PPU_WR", addr, value)

	local rv = dict.nes("NES_PPU_RD", addr)

	local i = 0

	while ( rv ~= value ) do
		rv = dict.nes("NES_PPU_RD", addr)
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
local function flash_prgrom(file, rom_size_KB, debug)

	--init_mapper()

	--test some bytes
	--wr_prg_flash_byte(0x8000, 0xA5, true)
	--wr_prg_flash_byte(0xFFFF, 0x5A, true)
	

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


--slow host flash one byte at a time...
--this is controlled from the host side byte by byte making it slow
--but doesn't require specific firmware MMC3 flashing functions
local function flash_chrrom(file, rom_size_KB, debug)

	--init_mapper()

	--test some bytes
	--wr_chr_flash_byte(0x0000, 0xC3, true)
	--wr_chr_flash_byte(0x1FFF, 0x3C, true)
	
	print("\nProgramming CHR-ROM flash")
      	--most of this is overkill for NROM, but it's how we want to handle things for bigger mappers

	local base_addr = 0x0000
	local bank_size = 8*1024 
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata

	while cur_bank < total_banks do

		if (cur_bank %8 == 0) then
			print("writting CHR bank: ", cur_bank, " of ", total_banks-1)
		end

		--program the entire bank's worth of data
		flash.write_file( file, 8, mapname, "CHRROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming CHR-ROM flash")
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

	local filetype = "nes"
	--local filetype = "bin"

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

--test the cart
	if test then
		print("Testing ", mapname)

		nes.detect_mapper_mirroring(true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	

	--	dict.io("SWIM_INIT", "SWIM_ON_A0")	
	--	if swim.start(true) then

	--		swim.read_stack()

	--	else
	--		print("ERROR trying to read back CIC signature stack data")
	--	end
	--	swim.stop_and_reset()

		--nes.read_flashID_prgrom_exp0(true)
		prgrom_manf_id(true)
		--nes.read_flashID_chrrom_8K(true)
		chrrom_manf_id(true)

	end

--change mirroring
	if mirror then
		--mirror set to "H" of "V" for desired mirroring
		print("Setting", mirror, "mirroring via CIC software mirror control")
		nes.detect_mapper_mirroring(true)

		ciccom.start()
		ciccom.set_opcode("M")
		--now send operand "V" (0x56) or "H" (0x48)
		ciccom.write(mirror)

		dict.io("IO_RESET")	
		ciccom.sleep(0.01) --10msec to be overly safe

		--test reading back CIC version
		dict.io("SWIM_INIT", "SWIM_ON_A0")	
		--dict.io("SWIM_INIT", "SWIM_ON_EXP0")	
		if swim.start(true) then

			swim.read_stack()

		else
			print("ERROR trying to read back CIC signature stack data")
		end
		swim.stop_and_reset()

		print("done reading STM8 stack on A0\n")

		dict.io("IO_RESET")	
		dict.io("NES_INIT")
		nes.detect_mapper_mirroring(true)
	end

--dump the cart to dumpfile
	if read then

		print("\nDumping PRG & CHR ROMs...")

		--init_mapper()
		
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

		print("\nErasing ", mapname);

		--init_mapper()

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

		print("erasing CHR-ROM");
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
		dict.nes("NES_PPU_WR", 0x1555, 0x80)
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
		dict.nes("NES_PPU_WR", 0x1555, 0x10)
		rv = dict.nes("NES_PPU_RD", 0x0000)

		i = 0
		while ( rv ~= 0xFF ) do
			rv = dict.nes("NES_PPU_RD", 0x0000)
			i = i + 1
		end
		print(i, "naks, done erasing chr.\n");
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
		--flash.write_file( file, 32, "NROM", "PRGROM", true )
		--flash.write_file( file, 8, "NROM", "CHRROM", true )
		flash_prgrom(file, prg_size, true)
		flash_chrrom(file, chr_size, true)
		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually
		print("\nPost dumping PRG & CHR ROMs...")

		--init_mapper()

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
nrom.process = process

-- return the module's table
return nrom
