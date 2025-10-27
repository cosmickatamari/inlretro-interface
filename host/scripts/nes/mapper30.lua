
-- create the module's table
local mapper30 = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local time = require "scripts.app.time"
local buffers = require "scripts.app.buffers"

-- file constants
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
	local filetype = "nes"
	--local filetype = "bin"

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

--test cart by reading manf/prod ID
	if test then
		print("mapper 30")
		nes.detect_mapper_mirroring(true)
		nes.ppu_ram_sense(0x1000, true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	

		prgrom_manf_id( debug )

		--test CHR-RAM banking
		dict.nes("NES_CPU_WR", 0xC000, 0x00) --CHR bank 0
		dict.nes("NES_PPU_WR", 0x0000, 0xAA)
		dict.nes("NES_CPU_WR", 0xC000, 0x20) --CHR bank 1
		dict.nes("NES_PPU_WR", 0x0000, 0x55)
		dict.nes("NES_CPU_WR", 0xC000, 0x40) --CHR bank 2
		dict.nes("NES_PPU_WR", 0x0000, 0xCC)
		dict.nes("NES_CPU_WR", 0xC000, 0x60) --CHR bank 3
		dict.nes("NES_PPU_WR", 0x0000, 0x33)

		--read back
		---[[
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
		end
		--]]
		

	end

--dump the cart to dumpfile
	if read then
		file = assert(io.open(dumpfile, "wb"))

		--create header: pass open & empty file & rom sizes
		create_header(file, prg_size, chr_size)

		--dump cart into file
		dump.dumptofile( file, prg_size, "MAP30", "PRGROM", true )

		--close file
		assert(file:close())
	end


--erase the cart
	if erase then


		print("\nerasing mapper 30");

		print("erasing PRG-ROM");
		dict.nes("NES_CPU_WR", 0xC000, 0x01)
		dict.nes("NES_CPU_WR", 0x9555, 0xAA)

		dict.nes("NES_CPU_WR", 0xC000, 0x00)
		dict.nes("NES_CPU_WR", 0xAAAA, 0x55)

		dict.nes("NES_CPU_WR", 0xC000, 0x01)
		dict.nes("NES_CPU_WR", 0x9555, 0x80)

		dict.nes("NES_CPU_WR", 0xC000, 0x01)
		dict.nes("NES_CPU_WR", 0x9555, 0xAA)

		dict.nes("NES_CPU_WR", 0xC000, 0x00)
		dict.nes("NES_CPU_WR", 0xAAAA, 0x55)

		dict.nes("NES_CPU_WR", 0xC000, 0x01)
		dict.nes("NES_CPU_WR", 0x9555, 0x10)

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
		print("\nFLASHING the PRG-ROM, will take ~20sec please wait...")
		time.start()
		flash.write_file( file, prg_size, "MAP30", "PRGROM", false )
		time.report(prg_size)
		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		dump.dumptofile( file, prg_size, "MAP30", "PRGROM", true )

		--close file
		assert(file:close())
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
mapper30.process = process

-- return the module's table
return mapper30
