
-- create the module's table
local basic = {}

-- import required modules
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local help = require "scripts.app.help"
local time = require "scripts.app.time"

-- file constants
local mapname = "BASIC"	  --IDK what else to call it right now, no real mappers.  Just different save types

-- local functions


--dump the ROM
local function dump_rom( file, rom_size_KB, debug )


	--ROM ONLY dump all 32KB, most of this code is overkill for no MBC.
	--	but follows same format as MBC's
	local KB_per_read = 128	--read 16bit address space 2Bytes per address (2*64K = 128KByte)
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0	--this value doesn't matter, but dumptofile won't like it if it's nil


	--GBA roms increment themselves after each read.  So really only have to latch
	--the first address, then read out each byte sequentially..
	--The address provided for dumptofile doesn't actually do anything on the firmware side
	--The firmware keeps track of the address being currently read from
	--
	--One thing to note is that to aid in double buffering the firmware assumes the host will
	--want the next page and goes ahead and starts dumping it, once the last page was read.  
	--For parallel roms this doesn't matter when the page beyond a bank is read for no good.  
	--But for GBA the rom increments itself and will become unaligned with the host if one 
	--doesn't LATCH_ADDR before starting each dumptofile

	--[[
	-- Read entire rom at once:
	--latch address	       AD0-15  A16-23
	dict.gba("LATCH_ADDR", 0x0000, 0x00)

	dump.dumptofile( file, rom_size_KB, addr_base, "GBA_PAGE", false )

	dict.gba("RELEASE_BUS")
	--]]


	-- read 64K address space (128KByte) at a time just so we can report progress from here
	-- In practice the isn't a measureable speed difference comparared to reading the entire
	-- rom at once
	while ( read_count < num_reads ) do

		if (read_count %8 == 0) then
			print("Dumping ROM bank: ", read_count, " of ", num_reads-1)
		end

		--latch address	       AD0-15  A16-23
		dict.gba("LATCH_ADDR", 0x0000, read_count)

		dump.dumptofile( file, KB_per_read, addr_base, "GBA_ROM_PAGE", false )

		read_count = read_count + 1

		dict.gba("RELEASE_BUS")
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
	local rom_size = console_opts["rom_size_kbyte"]
	local wram_size = console_opts["wram_size_kb"]
	local mirror = console_opts["mirror"]

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("GBA_INIT")

	dict.io("GB_POWER_3V")	--GBA is 3v cartridge

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
		time.start()
		dump_rom(file, rom_size, false)
		time.report(rom_size)

		--close file
		assert(file:close())
		print("DONE Dumping ROM")
	end


--erase the cart
	if erase then

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
		time.start()
		dump_rom(file, rom_size, false)
		time.report(rom_size)

		--close file
		assert(file:close())

		print("DONE post dumping ROM")
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
basic.process = process

-- return the module's table
return basic
