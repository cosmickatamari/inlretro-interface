-- UNROM/UxROM mapper for INL Retro
-- Supports iNES mapper 2 (UNROM/UxROM)

local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"

local unrom = {}

-- File constants
local mapname = "UxROM"
local banktable_base = nil


-- local functions

local function create_header(file, prgKB, chrKB)
	local mirroring = nes.detect_mapper_mirroring()
	nes.write_header(file, prgKB, 0, op_buffer[mapname], mirroring)
end

local function init_mapper(debug)
	-- Need to select bank0 so PRG-ROM A14 is low when writing to lower bank
	-- TODO: This needs to be written to ROM where value is 0x00 due to bus conflicts
	-- So need to find the bank table first
	-- This could present an even larger problem with a blank flash chip
	-- Would have to get a byte written to 0x00 first before able to change the bank
	-- Becomes catch-22 situation. Will have to rely on MCU overpowering PRG-ROM
	-- A way out would be to disable the PRG-ROM with exp0 (/WE) going low
	-- For now the write below seems to be working fine though
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
end

-- Read PRG-ROM flash ID
local function prgrom_manf_id(debug)
	init_mapper()

	if debug then print("reading PRG-ROM manf ID") end

	-- Enter software ID mode
	-- ROMSEL controls PRG-ROM /OE which needs to be low for flash writes
	-- So unlock commands need to be addressed below $8000
	-- DISCRETE_EXP0_PRGROM_WR doesn't toggle /ROMSEL by definition though, so A15 is unused
	-- Address mapping: 0x5 = $5555, 0x2 = $2AAA
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x90)

	-- Read manufacturer ID
	local rv = dict.nes("NES_CPU_RD", 0x8000)
	if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end

	-- Read product ID
	rv = dict.nes("NES_CPU_RD", 0x8001)
	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end

	-- Exit software ID mode
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x8000, 0xF0)
end

-- Find a viable banktable location
local function find_banktable(banktable_size)
	local search_base = 0x0C  -- Search in $C000-$F000, the fixed bank
	local KB_search_space = 16

	-- Get the fixed bank's content
	local search_data = ""
	dump.dumptocallback(
		function(data)
			search_data = search_data .. data
		end,
		KB_search_space, search_base, "NESCPU_4KB", false
	)

	-- Construct the byte sequence that we need
	local searched_sequence = ""
	while (searched_sequence:len() < banktable_size) do
		searched_sequence = searched_sequence .. string.char(searched_sequence:len())
	end

	-- Search for the banktable in the fixed bank
	local position_in_fixed_bank = string.find(search_data, searched_sequence, 1, true)
	if (position_in_fixed_bank == nil) then
		return nil
	end

	-- Compute the CPU offset of this data
	return 0xC000 + position_in_fixed_bank - 1
end

-- Dump the PRG ROM
local function dump_prgrom(file, rom_size_KB, debug)
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x08  -- $8000

	while (read_count < num_reads) do
		if debug then print("dump PRG part", read_count, "of", num_reads) end

		-- Select desired bank to dump
		local bank_addr = banktable_base + read_count
		print("Selecting bank", read_count, "via address $" .. string.format("%X", bank_addr))
		dict.nes("NES_CPU_WR", bank_addr, read_count)  -- 16KB @ CPU $8000

		-- Test read to verify bank switching
		if debug then
			local test_bytes = {}
			for i = 0, 7 do
				test_bytes[i + 1] = dict.nes("NES_CPU_RD", 0x8000 + i)
			end
			print("Bank", read_count, "test read @ $8000:", string.format("%02X %02X %02X %02X %02X %02X %02X %02X",
				test_bytes[1], test_bytes[2], test_bytes[3], test_bytes[4],
				test_bytes[5], test_bytes[6], test_bytes[7], test_bytes[8]))
		end

		dump.dumptofile(file, KB_per_read, addr_base, "NESCPU_4KB", false)

		read_count = read_count + 1
	end
end


local function wr_prg_flash_byte(addr, value, bank, debug)
	dict.nes("NES_CPU_WR", banktable_base, 0x00)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xA0)
	dict.nes("NES_CPU_WR", banktable_base + bank, bank)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", addr, value)

	local rv = dict.nes("NES_CPU_RD", addr)
	local i = 0

	while (rv ~= value) do
		rv = dict.nes("NES_CPU_RD", addr)
		i = i + 1
	end
	if debug then print(i, "naks, done writing byte.") end
end

-- Write bank table
-- Base is the actual NES CPU address, not the ROM offset (e.g., $FFF0, not $7FF0)
local function wr_bank_table(base, entries, numtables)
	-- Need to have A14 clear when lower bank enabled
	init_mapper()

	-- UxROM can have a single bank table in $C000-FFFF (assuming this is most likely)
	-- or a bank table in all other banks in $8000-BFFF

	local i = 0
	while (i < entries) do
		wr_prg_flash_byte(base + i, i, 0)
		i = i + 1
	end

	-- TODO: verify the bank table was successfully written before continuing
end


-- Flash PRG ROM (controlled from host side one bank at a time)
-- Requires mapper specific firmware flashing functions
local function flash_prgrom(file, rom_size_KB, debug)
	init_mapper()

	-- Bank table should already be written

	print("\nProgramming PRG-ROM flash")

	local bank_size = 16 * 1024  -- UNROM 16KB per PRG bank
	local cur_bank = 0
	local total_banks = rom_size_KB * 1024 / bank_size

	-- Set the bank table address
	dict.nes("SET_BANK_TABLE", banktable_base)
	if debug then print("get banktable:", string.format("%X", dict.nes("GET_BANK_TABLE"))) end

	while cur_bank < total_banks do
		if (cur_bank % 4 == 0) then
			print("writing PRG bank:", cur_bank, "of", total_banks - 1)
		end

		-- Select bank to flash
		dict.nes("SET_CUR_BANK", cur_bank)
		if debug then print("get bank:", dict.nes("GET_CUR_BANK")) end

		-- Have the device write a bank's worth of data (same as NROM)
		flash.write_file(file, bank_size / 1024, mapname, "PRGROM", false)

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")
end



-- Cart should be in reset state upon calling this function
-- This function processes all user requests for this specific board/mapper
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

	-- Initialize device I/O for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

	-- Test cart by reading manufacturer/product ID
	if test then
		print("Testing", mapname)
		nes.detect_mapper_mirroring(true)
		nes.ppu_ram_sense(0x1000, true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))
		prgrom_manf_id(true)
	end

	-- Dump the cart to dumpfile
	if read then
		print("\nDumping PRG-ROM...")
		file = assert(io.open(dumpfile, "wb"))

		-- Find bank table to avoid bus conflicts
		if (banktable_base == nil) then
			local KB_per_bank = 16
			local bank_count = prg_size / KB_per_bank
			print("Searching for bank table with", bank_count, "entries")
			banktable_base = find_banktable(bank_count)
			if (banktable_base == nil) then
				print("BANKTABLE NOT FOUND - trying fallback addresses")
				-- Try some common bank table addresses
				local fallback_addrs = {0xE473, 0xCC84, 0x8000, 0xC000, 0xFD69}
				for i, addr in ipairs(fallback_addrs) do
					print("Trying fallback address $" .. string.format("%X", addr))
					banktable_base = addr
					break  -- Use first fallback for now
				end
			else
				print("found banktable addr = $" .. string.format("%X", banktable_base))
			end
		else
			print("Using hardcoded banktable addr = $" .. string.format("%X", banktable_base))
		end

		-- Create header: pass open & empty file & ROM sizes
		create_header(file, prg_size, chr_size)

		-- Dump cart into file
		dump_prgrom(file, prg_size, false)

		-- Close file
		assert(file:close())
		print("DONE Dumping PRG-ROM")
	end

	-- Erase the cart
	if erase then
		print("\nErasing", mapname)

		init_mapper()

		print("erasing PRG-ROM")
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x80)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x10)
		rv = dict.nes("NES_CPU_RD", 0x8000)

		local i = 0
		while (rv ~= 0xFF) do
			rv = dict.nes("NES_CPU_RD", 0x8000)
			i = i + 1
		end
		print(i, "naks, done erasing prg.")
	end

	-- Program flashfile to the cart
	if program then
		file = assert(io.open(flashfile, "rb"))
		-- Determine if auto-doubling, deinterleaving, etc. needs done to make board compatible with ROM

		-- Find bank table in the ROM
		-- Write bank table to all banks of cartridge
		wr_bank_table(banktable_base, prg_size / 16)  -- 16KB per bank gives number of entries

		-- Flash cart
		flash_prgrom(file, prg_size, false)

		-- Close file
		assert(file:close())
	end

	-- Verify flashfile is on the cart
	if verify then
		print("\nPost dumping PRG-ROM")

		file = assert(io.open(verifyfile, "wb"))

		-- Dump cart into file
		dump_prgrom(file, prg_size, false)

		-- Close file
		assert(file:close())

		print("DONE post dumping PRG-ROM")
	end

	dict.io("IO_RESET")
end

-- Functions other modules are able to call
unrom.process = process

-- Return the module's table
return unrom