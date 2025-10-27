-- create the module's table
local romonly = {}

-- import required modules
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local files = require "scripts.app.files"
local jtag = require "scripts.jtag.jtag"

-- file constants
local mapname = "ROMONLY"

-- local functions
local function unsupported(operation)
	print("\nUNSUPPORTED OPERATION: \"" .. operation .. "\" not implemented yet for Gameboy - ".. mapname .. "\n")
end

-- dump the ROM
local function dump_rom(file, rom_size_KB, debug)

	--ROM ONLY dump all 32KB, most of this code is overkill for no MBC.
	--	but follows same format as MBC's
	local KB_per_read = 32	--$0000-7FFF is ROM space (32KByte)
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00	-- $0000 base address for ROM

	while (read_count < num_reads) do

		if debug then print("dump ROM part ", read_count, " of ", num_reads) end

		dump.dumptofile(file, KB_per_read, addr_base, "GAMEBOY_PAGE", false)

		read_count = read_count + 1
	end

end

-- Cart should be in reset state upon calling this function 
-- this function processes all user requests for this specific board/mapper
local function process(process_opts, console_opts)
	local file 

    -- initialize device i/o for Gameboy
	dict.io("IO_RESET")
	dict.io("GAMEBOY_INIT")
	dict.io("GB_POWER_5V")	--gameboy carts prob run fine at 3v if want to be safe

    -- test the cart
	if process_opts["test"] then
		print("no test function yet")
--		unsupported("test")	

		-- 5v - 3v power cycle test
		--[[ 
		dict.io("GB_POWER_3V")
		print("GBP high 3v GBA")
		jtag.sleep(1)
		dict.io("GB_POWER_5V")
		print("GBP low 5v GB")
		jtag.sleep(1)
		dict.io("GB_POWER_3V")
		print("GBP high 3v GBA")
		jtag.sleep(1)
		dict.io("GB_POWER_5V")
		print("GBP low 5v GB")
		jtag.sleep(1)
		print("GBP reset (pullup) = 3v")
		--]]
	end

    -- dump the cart to dumpfile
	if process_opts["read"] then

		print("\nDumping ROM...")
		
		file = assert(io.open(process_opts["dump_filename"], "wb"))

		-- dump cart into file
		dump_rom(file, console_opts["rom_size_kbyte"], false)

		-- close file
		assert(file:close())
		print("DONE Dumping ROM")
	end

    -- TODO: Erase the cart
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

		if (files.compare( process_opts["verify_filename"], "ignore/Boxxle.gb", true ) ) then
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
romonly.process = process

-- return the module's table
return romonly
