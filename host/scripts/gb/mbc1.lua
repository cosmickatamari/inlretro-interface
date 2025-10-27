
-- create the module's table
local mbc1 = {}

-- import required modules
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local files = require "scripts.app.files"

-- file constants
local mapname = "MBC1"

-- local functions

local function unsupported(operation)
	print("\nUNSUPPORTED OPERATION: \"" .. operation .. "\" not implemented yet for Gameboy - ".. mapname .. "\n")
end

--dump the ROM
local function dump_rom( file, rom_size_KB, debug )


	--ROM ONLY dump all 32KB, most of this code is overkill for no MBC.
	--	but follows same format as MBC's
	local KB_per_read = 16	--read half the ROM space (16KByte)
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00	-- $0000 base address for ROM

	--the first bank is fixed & only visible at $0000-3FFF
	if debug then print( "dump ROM part ", read_count, " of ", num_reads) end
	dump.dumptofile( file, KB_per_read, addr_base, "GAMEBOY_PAGE", false )
	read_count = 1

	--remaining banks must be read from $4000-7FFF
	addr_base = 0x40
	--banks 0x20, 0x40, 0x60 are not visible, they present 0x21, 0x41, 0x61 instead
	--much like how 0x00 would present 0x01 at $4000-7FFF
	--so there's a max of 125 banks because of these 3 lost banks.. (almost 2MByte)
	--this doesn't affect roms that are 512KByte or less because they only
	--use mapper bits 5-0, and bits 6 & 7 are the ones that are affected by this.

	while ( read_count < num_reads ) do

		--select the current bank (write to $2000-3FFF)
		dict.gameboy("GAMEBOY_WR", 0x2000, read_count)
		--I'm assuming MBC isn't subject to bus conflicts...

		if debug then print( "dump ROM part ", read_count, " of ", num_reads) end

		dump.dumptofile( file, KB_per_read, addr_base, "GAMEBOY_PAGE", false )

		read_count = read_count + 1
	end

end


-- Cart should be in reset state upon calling this function 
-- this function processes all user requests for this specific board/mapper
local function process(process_opts, console_opts)
	local file 

	-- Initialize device i/o for Gameboy
	dict.io("IO_RESET")
	dict.io("GAMEBOY_INIT")

	dict.io("GB_POWER_5V")	-- Gameboy carts prob run fine at 3v if want to be safe

	-- TODO: test the cart
	if process_opts["test"] then
		print("no test function yet")
		--unsupported("test")
	end

	-- Dump the cart to dumpfile
	if process_opts["read"] then

		print("\nDumping ROM...")
		
		file = assert(io.open(process_opts["dump_filename"], "wb"))

		-- Dump cart into file
		dump_rom(file, console_opts["rom_size_kbyte"], false)

		-- Close file
		assert(file:close())
		print("DONE Dumping ROM")
	end


	-- TODO: erase the cart
	if process_opts["erase"] then
		unsupported("erase")
	end


	-- TODO: program flashfile to the cart
	if process_opts["program"] then
		unsupported("program")
	end

	-- Verify flashfile is on the cart
	-- (This is sort of pointless until "program" is supported)
	if process_opts["verify"] then
		--for now let's just dump the file and verify manually
		print("\nPost dumping ROM...")

		file = assert(io.open(process_opts["verify_filename"], "wb"))

		--dump cart into file
		dump_rom(file, console_opts["rom_size_kbyte"], false)

		--close file
		assert(file:close())

		print("DONE post dumping ROM")
		if (files.compare( process_opts["verify_filename"], "ignore/madden96_bank0.gb", true ) ) then
			print("\nSUCCESS! Flash verified")
		else
			print("\n\n\n FAILURE! Flash verification did not match")
		end
	end

	dict.io("IO_RESET")
end

-- global variables so other modules can use them
--    NONE

-- call functions desired to run when script is called/imported
--    NONE

-- functions other modules are able to call
mbc1.process = process

-- return the module's table
return mbc1
