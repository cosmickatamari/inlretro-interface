
-- create the module's table
local genesis_v1 = {}

-- import required modules
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"

-- file constants

-- local functions

local function unsupported(operation)
	print("\nUNSUPPORTED OPERATION: \"" .. operation .. "\" not implemented yet for Sega Genesis.\n")
end

-- Compute Genesis checksum from a file, which can be compared with header value.
local function checksum_rom(filename)
	local file = assert(io.open(filename, "rb"))
	local sum = 0
	-- Skip header
	file:read(0x200)
	while true do
		-- Add up remaining 16-bit words
		local bytes = file:read(2)
		if not bytes then break end
		sum = sum + string.unpack(">i2", bytes)
	end
	-- Only use the lower bits.
	return sum & 0xFFFF
end

--/ROMSEL is always low for this dump
local function dump_rom( file, rom_size_KB, debug )

	local KB_per_bank = 128	  -- A1-16 = 64K address space, 2Bytes per address
	local addr_base = 0x0000  -- control signals are manually controlled


	local num_reads = rom_size_KB / KB_per_bank
	local read_count = 0

	while (read_count < num_reads) do

		if debug then print( "Dumping ROM part ", read_count + 1, " of ", num_reads) end

		-- A "large" Genesis ROM is 24 banks, many are 8 and 16 - status every 4 is reasonable.
		-- The largest published Genesis game is Super Street Fighter 2, which is 40 banks!
		-- TODO: Accessing banks in games that are >4MB require using a mapper.
		-- See: https://plutiedev.com/beyond-4mb

		if (read_count % 4 == 0) then
			print("dumping ROM bank: ", read_count, " of ", num_reads - 1)
		end

		-- Select desired bank.
		dict.sega("GEN_SET_BANK", read_count)

		dump.dumptofile(file, KB_per_bank/2, addr_base, "GENESIS_ROM_PAGE0", debug)
		dump.dumptofile(file, KB_per_bank/2, addr_base, "GENESIS_ROM_PAGE1", debug)

		read_count = read_count + 1
	end

end

-- Helper to extract fields in internal header.
local function extract_field_from_string(data, start_offset, length)
	-- 1 is added to Offset to handle lua strings being 1-based.
	return string.sub(data, start_offset + 1, start_offset + length)
end

-- Populates table with internal header contents from dumped data.
local function extract_header(header_data)
	-- https://plutiedev.com/rom-header
	-- https://en.wikibooks.org/wiki/Genesis_Programming#ROM_header
	
	-- TODO: Decode publisher from t-series in build field
	-- https://segaretro.org/Third-party_T-series_codes

	local addr_console_name 		= 0x100
	local addr_build_date 			= 0x110
	local addr_domestic_name 		= 0x120
	local addr_intl_name 			= 0x150
	local addr_type_serial_version 	= 0x180
	local addr_checksum 			= 0x18E
	local addr_device_support 		= 0x190
	local addr_rom_addr_range 		= 0x1A0
	local addr_ram_addr_range 		= 0x1A8
	local addr_sram_support 		= 0x1B0
	local addr_modem_support 		= 0x1BC
	local addr_region_support 		= 0x1F0

	local len_console_name = 16
	local len_build_date = 16
	local len_name = 48
	local len_type_serial_version = 14
	local len_checksum = 2
	local len_device_support = 16
	local len_addr_range = 8
	local len_sram_support = 12
	local len_modem_support = 12
	local len_region_support = 3

	local header = {
		console_name = extract_field_from_string(header_data, addr_console_name, len_console_name),
		-- TODO: Decode T-Value and build info.
		build_date = extract_field_from_string(header_data, addr_build_date, len_build_date),
		domestic_name = extract_field_from_string(header_data, addr_domestic_name, len_name),
		international_name = extract_field_from_string(header_data, addr_intl_name, len_name),
		-- TODO: Decode Type, serial and revision.
		type_serial_version = extract_field_from_string(header_data, addr_type_serial_version, len_type_serial_version),
		checksum = string.unpack(">i2", extract_field_from_string(header_data, addr_checksum, len_checksum)), 
		-- TODO: Decode device support.
		io_device_support = extract_field_from_string(header_data, addr_device_support, len_device_support),
		-- TODO: Decode SRAM support.
		sram_support = extract_field_from_string(header_data, addr_sram_support, len_sram_support),
		-- TODO: Decode modem support.
		modem_support = extract_field_from_string(header_data, addr_modem_support, len_modem_support),
		-- TODO: Decode region support.
		region_support = extract_field_from_string(header_data, addr_region_support, len_region_support),
	}
	-- ROM range can be used to autodetect the rom size.
	local rom_range = extract_field_from_string(header_data, addr_rom_addr_range, len_addr_range)
	local rom_start = string.unpack(">i4", string.sub(rom_range, 1, 4))
	local rom_end = string.unpack(">i4", string.sub(rom_range,5, 8))
	header["rom_size"] = (rom_end - rom_start + 1) / 1024

	-- These should be the same in every cart according to docs, but decode in case its not. (64 Kb)
	local ram_range = extract_field_from_string(header_data, addr_ram_addr_range, len_addr_range)
	local ram_start = string.unpack(">i4", string.sub(ram_range, 1, 4))
	local ram_end = string.unpack(">i4", string.sub(ram_range,5, 8))
	header["ram_size"] = (ram_end - ram_start + 1) / 1024
	
	return header
end

-- Make a human-friendly text representation of ROM Size.
local function str_rom_size(rom_size_kb)
	local mbit = rom_size_kb / 128
	if mbit < 1 then
		mbit = "<1"
	end
	return "" .. rom_size_kb .. " kB (".. mbit .." mbit)" 
end

-- Prints parsed header contents to stdout.
local function print_header(genesis_header)
	print("Console Name: \t" .. genesis_header["console_name"])
	print("Domestic Name: \t" .. genesis_header["domestic_name"])
	print("Release Date: \t" .. genesis_header["build_date"])
	print("Rom Size: \t" .. str_rom_size(genesis_header["rom_size"]))
	print("Serial/Version: " .. genesis_header["type_serial_version"])
	print("Checksum: \t" .. hexfmt(genesis_header["checksum"]))
end

-- Reads and parses internal ROM header from first page of data.
local function read_header()
	dict.sega("GEN_SET_BANK", 0)

	local page0_data = ""
	dump.dumptocallback(
		function (data)
			page0_data = page0_data .. data
		end,
		64, 0x0000, "GENESIS_ROM_PAGE0", false
	)
	local header_data = string.sub(page0_data, 1, 0x201)
	local genesis_header = extract_header(header_data)
	return genesis_header
end

-- Test that cartridge is readable by looking for valid entries in internal header.
local function test(genesis_header)
	local valid = false
	-- Trailing spaces are required! Field length is 16 characters.
	if genesis_header["console_name"] == "SEGA GENESIS    " then valid = true end
	if genesis_header["console_name"] == "SEGA MEGA DRIVE " then valid = true end
	return valid
end

--Cart should be in reset state upon calling this function 
--this function processes all user requests for this specific board/mapper
local function process(process_opts, console_opts)
	local file 

    -- Initialize device i/o for SEGA
	dict.io("IO_RESET")
	dict.io("SEGA_INIT")
	local genesis_header = read_header()

	if process_opts["test"] then
		-- If garbage data is in the header, it's a waste of time trying to proceed doing anything else.
		local valid_header = test(genesis_header)
		if valid_header ~= true then print("Unreadable cartridge - exiting! (Try cleaning cartridge connector?)") end
		assert(valid_header)
		print_header(genesis_header)
	end

	-- TODO: dump the ram to file 
	if dumpram then
		unsupported("dumpram")
	end

	-- Dump the cart to dumpfile.
	if process_opts["read"] then
		
		-- If ROM size wasn't provided, attempt to use value in internal header.
		local rom_size = console_opts["rom_size_kbyte"]
		if rom_size == 0 or rom_size == nil then
			print("ROM Size not provided, " .. str_rom_size(genesis_header["rom_size"]) .. " detected.")
			rom_size = genesis_header["rom_size"]
		end

		print("\nDumping SEGA ROM...")
		file = assert(io.open(process_opts["dump_filename"], "wb"))
		
		--dump cart into file
		dump_rom(file, rom_size, false)

		--close file
		assert(file:close())
		print("DONE Dumping SEGA ROM")
		print("Computing checksum...")
		local checksum = checksum_rom(process_opts["dump_filename"])
		if checksum == genesis_header["checksum"] then
			print("CHECKSUM OK! DUMP SUCCESS!")
		else
			print("CHECKSUM MISMATCH - BAD DUMP! (Try cleaning cartridge connector?)")
		end
	end

	-- TODO: erase the cart
	if process_opts["erase"] then
		unsupported("erase")
	end

	-- TODO: write to wram on the cart
	if writeram then
		unsupported("writeram")
	end

	-- TODO: program flashfile to the cart
	if process_opts["program"] then
		unsupported("program")
	end

	-- TODO: verify flashfile is on the cart
	if process_opts["verify"] then
		unsupported("verify")
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them
--    NONE

-- call functions desired to run when script is called/imported
--    NONE

-- functions other modules are able to call
genesis_v1.process = process

-- return the module's table
return genesis_v1
