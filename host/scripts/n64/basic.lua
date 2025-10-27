
-- create the module's table
local n64 = {}

-- import required modules
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local help = require "scripts.app.help"
local time = require "scripts.app.time"

-- file constants

-- local functions

--dump the SNES ROM starting at the provided bank
--/ROMSEL is always low for this dump
local function dump_rom( file, rom_size_KB, debug )

	local KB_per_bank = 64 --AD0-15 = 64K address space, A0 ignored so 1Byte per address!
	local addr_base = 0x0000  -- control signals are manually controlled

	local bank_base = 0x1000  --N64 roms start at address 0x1000_0000

	local num_reads = rom_size_KB / KB_per_bank
	local read_count = 0
--	local read_count = 512 --second half of RE2


	--[[
	dict.n64("N64_SET_BANK", bank_base + 0)
	dict.n64("N64_LATCH_ADDR", 0x0000)
	print("read: ", help.hex(dict.n64("N64_RD")))
	print("read: ", help.hex(dict.n64("N64_RD")))
	dict.n64("N64_SET_BANK", bank_base + 0)
	dict.n64("N64_LATCH_ADDR", 0x0000)
	dump.dumptofile( file, KB_per_bank, addr_base, "N64_ROM_PAGE", false )

	dict.n64("N64_LATCH_ADDR", 0x0000)
	print("read: ", help.hex(dict.n64("N64_RD")))
	print("read: ", help.hex(dict.n64("N64_RD")))
	dict.n64("N64_LATCH_ADDR", 0x0000)
	dump.dumptofile( file, KB_per_bank, addr_base, "N64_ROM_PAGE", false )
	--]]

	while ( read_count < num_reads ) do

		if debug then print( "dump ROM part ", read_count, " of ", num_reads) end

		if (read_count %8 == 0) then
			print("dumping ROM bank: ", read_count, " of ", num_reads-1)
		end

		--select desired bank
		dict.n64("N64_SET_BANK", (bank_base+read_count))

		--dump a 64KByte chunk of rom
		dump.dumptofile( file, KB_per_bank, addr_base, "N64_ROM_PAGE", false )

		--prob don't need this till done..
		dict.n64("N64_RELEASE_BUS")

		read_count = read_count + 1
	end

	dict.n64("N64_RELEASE_BUS")

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
	local rom_size = console_opts["rom_size_kbyte"]
	local wram_size = console_opts["wram_size_kb"]
	local mirror = console_opts["mirror"]


--initialize device i/o for N64
	dict.io("IO_RESET")
	dict.io("N64_INIT")


--test cart by reading manf/prod ID
	if test then

		--read rom header
		print("\nN64 attempt to read in rom header:")

		local bank_base = 0x1000  --N64 roms start at address 0x1000_0000
		dict.n64("N64_SET_BANK", bank_base + 0)

		local i = 0, rv

		local header = {}
		local header_start = 0x0020
		dict.n64("N64_LATCH_ADDR", header_start)

		local header_len = 32 
		while i < header_len do

			rv = dict.n64("N64_RD")
			header[i+1] = rv>>8
			i = i+1
			header[i+1] = (rv & 0x00FF)
			i = i+1
		end
	
		i = 1
		while header[i] do
			io.write(string.char(header[i]))
			--io.write("B-",i,"=",header[i], " ")
			i = i+1
		end
		print("\n")


--		print("Testing SNES board");
--
--		--SNES detect HiROM or LoROM & RAM
--
--		--SNES detect if able to read flash ID's
--		if not rom_manf_id(true) then
--			print("ERROR unable to read flash ID")
--			return
--		end
	end


--dump the ram to file 
	if dumpram then

--		print("\nDumping SAVE RAM...")
--
--		--may have to verify /RESET is high to enable SRAM
--
--		file = assert(io.open(ramdumpfile, "wb"))
--
--		--dump cart into file
--		dump_ram(file, rambank, ram_size, snes_mapping, true)
--
--		--may disable SRAM by placing /RESET low
--
--		--close file
--		assert(file:close())
--
--		print("DONE Dumping SAVE RAM")
	end

--dump the cart to dumpfile
	if read then
		print("\nDumping N64 ROM...")
		print("Ouput format is Big Endian (.z64 format)")

		file = assert(io.open(dumpfile, "wb"))

		--dump cart into file
		time.start()
		dump_rom(file, rom_size, false)
		time.report(rom_size)

		--close file
		assert(file:close())
		print("DONE Dumping N64 ROM")
	end

--erase the cart
	if erase then

	--	erase_flash()
	end

--write to wram on the cart
	if writeram then

--		print("\nWritting to SAVE RAM...")
--
--		file = assert(io.open(ramwritefile, "rb"))
--
--		--flash.write_file( file, ram_size, "NOVAR", "PRGRAM", false )
--		--flash.write_file( file, ram_size, "LOROM_3VOLT", "SNESROM", false )
--		wr_ram(file, rambank, ram_size, snes_mapping, true)
--
--		--close file
--		assert(file:close())
--
--		print("DONE Writting SAVE RAM")
	end


--program flashfile to the cart
	if program then

--		--open file
--		file = assert(io.open(flashfile, "rb"))
--		--determine if auto-doubling, deinterleaving, etc, 
--		--needs done to make board compatible with rom
--
--		--flash cart
--		flash_rom(file, rom_size, snes_mapping, true)
--
--		--close file
--		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
--		print("\nPost dumping SNES ROM...")
--		--for now let's just dump the file and verify manually
--
--		file = assert(io.open(verifyfile, "wb"))
--
--		--dump cart into file
--		dump_rom(file, rom_size, false)
--
--		--close file
--		assert(file:close())
--		print("DONE Post dumping SNES ROM")
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
n64.process = process

-- return the module's table
return n64
