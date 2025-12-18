-- MMC3 mapper for INL Retro
-- Supports iNES mapper 4 (MMC3)

local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local time = require "scripts.app.time"
local files = require "scripts.app.files"

local mmc3 = {}

-- File constants
local mapname = "MMC3"

-- local functions

-- Game detection based on actual ROM content analysis
local function detect_game_type()
	-- Do minimal setup to read from PRG ROM
	dict.nes("NES_CPU_WR", 0xA001, 0x40)  -- Disable WRAM
	dict.nes("NES_CPU_WR", 0xA000, 0x00)  -- Set vertical mirroring
	
	-- Set up basic CHR banks
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	dict.nes("NES_CPU_WR", 0x8001, 0x00)  -- 2KB @ PPU $0000
	dict.nes("NES_CPU_WR", 0x8000, 0x01)
	dict.nes("NES_CPU_WR", 0x8001, 0x02)  -- 2KB @ PPU $0800
	
	-- Try to read some bytes from PRG ROM
	local byte1 = dict.nes("NES_CPU_RD", 0x8000)
	local byte2 = dict.nes("NES_CPU_RD", 0x8001)
	local byte3 = dict.nes("NES_CPU_RD", 0x8002)
	local byte4 = dict.nes("NES_CPU_RD", 0x8003)
	local byte5 = dict.nes("NES_CPU_RD", 0x8004)
	
	print("DEBUG: Read bytes:", string.format("0x%02X 0x%02X 0x%02X 0x%02X 0x%02X", byte1, byte2, byte3, byte4, byte5))
	
	-- Check for Super Mario 3 signature: 0x4C, 0x00, 0x80 (JMP $8000)
	if byte1 == 0x4C and byte2 == 0x00 and byte3 == 0x80 then
		print("DEBUG: Detected Super Mario 3 - using standard approach")
		return "standard"
	end
	
	-- Check for Mega Man 3 signature: Look for common patterns
	-- Mega Man games often have specific patterns
	if byte1 == 0x20 and byte2 == 0x00 and byte3 == 0x80 then  -- JSR $8000
		print("DEBUG: Detected Mega Man 3 - using custom approach")
		return "custom"
	end
	
	-- Check for Mega Man 3 actual signature: 0x90 0x90 0x90 0x90 0x98
	if byte1 == 0x90 and byte2 == 0x90 and byte3 == 0x90 and byte4 == 0x90 and byte5 == 0x98 then
		print("DEBUG: Detected Mega Man 3 (actual signature) - using custom approach")
		return "custom"
	end
	
	-- Check for other patterns that might indicate Mega Man 3
	if byte1 == 0x4C and byte2 == 0x00 and byte3 == 0x80 and byte4 == 0x20 then
		print("DEBUG: Detected possible Mega Man 3 variant - using custom approach")
		return "custom"
	end
	
	-- Default to standard approach for unknown games
	print("DEBUG: Unknown game - defaulting to standard approach")
	return "standard"
end

local function create_header(file, prgKB, chrKB)
	-- MMC3 is mapper 4, use vertical mirroring
	print("DEBUG: Creating header with mapper=4, mirroring=VERT")
	
	-- Write exactly 16 bytes for iNES header
	local header = "NES" ..
		string.char(0x1A) ..        -- Bytes 0-3: "NES" + EOF
		string.char(prgKB / 16) ..  -- Byte 4: PRG-ROM banks (16KB units)
		string.char(chrKB / 8) ..   -- Byte 5: CHR-ROM banks (8KB units)
		string.char(0x40) ..        -- Byte 6: Mapper 4 + VERT
		string.char(0x08) ..        -- Byte 7: Upper mapper bits
		string.char(0x00) ..        -- Byte 8: Mapper MSB
		string.char(0x00) ..        -- Byte 9: PRG/CHR size MSB
		string.char(0x00) ..        -- Byte 10: RAM size
		string.char(0x00) ..        -- Byte 11: TV system
		string.char(0x00) ..        -- Byte 12: TV system + misc
		string.char(0x00) ..        -- Byte 13: Unused
		string.char(0x00) ..        -- Byte 14: Unused
		string.char(0x01)           -- Byte 15: Unused (match No-Intro)
	
	file:write(header)
	
	-- Force flush to ensure header is written
	file:flush()
	
	print("DEBUG: Manual header written - 16 bytes total")
end


-- Initialize mapper for dumping (minimal setup, neutral CHR bank setup)
local function init_mapper_dump(debug)
	-- For save data safety start by disabling WRAM, and deny writes
	dict.nes("NES_CPU_WR", 0xA001, 0x40)
	
	-- Set mirroring
	dict.nes("NES_CPU_WR", 0xA000, 0x00)  -- bit0 0-vert 1-horiz

	-- MMC3B-specific initialization
	-- Clear any pending IRQ
	dict.nes("NES_CPU_WR", 0xE000, 0x00)  -- IRQ disable
	dict.nes("NES_CPU_WR", 0xE001, 0x00)  -- IRQ acknowledge

	-- Set up PRG-ROM banking for dumping
	-- Set PRG-ROM bank mode to 0 (swappable at $8000-$9FFF, fixed at $C000-$DFFF)
	-- No CHR A12 inversion for neutral setup
	dict.nes("NES_CPU_WR", 0x8000, 0x00)  -- bit 7 = 0 for no CHR A12 inversion, bit 6 = 0 for PRG mode 0
	dict.nes("NES_CPU_WR", 0x8001, 0x00)  -- dummy write

	-- Set up initial PRG banks for dumping
	dict.nes("NES_CPU_WR", 0x8000, 0x06)
	dict.nes("NES_CPU_WR", 0x8001, 0x00)  -- 8KB @ CPU $8000 (bank 0)

	dict.nes("NES_CPU_WR", 0x8000, 0x07)
	dict.nes("NES_CPU_WR", 0x8001, 0x01)  -- 8KB @ CPU $A000 (bank 1)

	-- Set up neutral CHR banks - use sequential values starting from 0
	-- This provides a more generic setup that should work for most games
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	dict.nes("NES_CPU_WR", 0x8001, 0x00)  -- 2KB @ PPU $0000 (bank 0)

	dict.nes("NES_CPU_WR", 0x8000, 0x01)
	dict.nes("NES_CPU_WR", 0x8001, 0x01)  -- 2KB @ PPU $0800 (bank 1)

	-- Set up 1KB CHR banks with sequential values
	dict.nes("NES_CPU_WR", 0x8000, 0x02)
	dict.nes("NES_CPU_WR", 0x8001, 0x02)  -- 1KB @ PPU $1000 (bank 2)
	
	dict.nes("NES_CPU_WR", 0x8000, 0x03)
	dict.nes("NES_CPU_WR", 0x8001, 0x03)  -- 1KB @ PPU $1400 (bank 3)

	dict.nes("NES_CPU_WR", 0x8000, 0x04)
	dict.nes("NES_CPU_WR", 0x8001, 0x04)  -- 1KB @ PPU $1800 (bank 4)

	dict.nes("NES_CPU_WR", 0x8000, 0x05)
	dict.nes("NES_CPU_WR", 0x8001, 0x05)  -- 1KB @ PPU $1C00 (bank 5)
end

-- Disables WRAM, selects Vertical mirroring
-- Sets up CHR-ROM flash PT0 for DATA, Commands: $5555->$1555  $2AAA->$1AAA
-- Sets up PRG-ROM flash DATA: $8000-9FFF, Commands: $5555->D555  $2AAA->$AAAA
-- Leaves reg0 selected (CHR bank & $0000) selected so PRG DATA writes don't change PRG banks
local function init_mapper(debug)


	-- For save data safety start by disabling WRAM, and deny writes
	dict.nes("NES_CPU_WR", 0xA001, 0x40)
	
	-- Set mirroring
	dict.nes("NES_CPU_WR", 0xA000, 0x00)  -- bit0 0-vert 1-horiz

	-- MMC3 bank select register ($8000-9FFE even):
	-- Bit 7: CHR A12 inversion
	-- Bit 6: PRG ROM bank mode
	-- Bits 2-0: Specify which bank register to update on next write to Bank Data register
	--   0: Select 2 KB CHR bank at PPU $0000-$07FF (or $1000-$17FF)
	--   1: Select 2 KB CHR bank at PPU $0800-$0FFF (or $1800-$1FFF)
	--   2: Select 1 KB CHR bank at PPU $1000-$13FF (or $0000-$03FF)
	--   3: Select 1 KB CHR bank at PPU $1400-$17FF (or $0400-$07FF)
	--   4: Select 1 KB CHR bank at PPU $1800-$1BFF (or $0800-$0BFF)
	--   5: Select 1 KB CHR bank at PPU $1C00-$1FFF (or $0C00-$0FFF)
	--   6: Select 8 KB PRG ROM bank at $8000-$9FFF (or $C000-$DFFF)
	--   7: Select 8 KB PRG ROM bank at $A000-$BFFF

	-- For CHR-ROM flash writes, use lower 4KB (PT0) for writing data & upper 4KB (PT1) for commands
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	dict.nes("NES_CPU_WR", 0x8001, 0x00)  -- 2KB @ PPU $0000

	dict.nes("NES_CPU_WR", 0x8000, 0x01)
	dict.nes("NES_CPU_WR", 0x8001, 0x02)  -- 2KB @ PPU $0800

	-- Use lower half of PT1 for $5555 commands
	dict.nes("NES_CPU_WR", 0x8000, 0x02)
	dict.nes("NES_CPU_WR", 0x8001, 0x15)  -- 1KB @ PPU $1000
	
	dict.nes("NES_CPU_WR", 0x8000, 0x03)
	dict.nes("NES_CPU_WR", 0x8001, 0x15)  -- 1KB @ PPU $1400

	-- Use upper half of PT1 for $2AAA commands
	dict.nes("NES_CPU_WR", 0x8000, 0x04)
	dict.nes("NES_CPU_WR", 0x8001, 0x0A)  -- 1KB @ PPU $1800

	dict.nes("NES_CPU_WR", 0x8000, 0x05)
	dict.nes("NES_CPU_WR", 0x8001, 0x0A)  -- 1KB @ PPU $1C00

	-- For PRG-ROM flash writes:
	-- Mode 0: $C000-FFFF fixed to last 16KB
	--         reg6 controls $8000-9FFF ($C000-DFFF in mode 1)
	--         reg7 controls $A000-BFFF (regardless of mode)
	-- Don't want to write data to $8000-9FFF because those are the bank regs
	-- Writing data to $A000-BFFF is okay as that will only affect mirroring and WRAM ctl
	-- $5555 commands can be written to $D555 (A14 set, A13 clear)
	-- $2AAA commands must be written through reg6/7 ($8000-BFFF) to clear A14 & set A13
	--     reg7 ($A000-BFFF) is ideal because it won't affect banking, just mirror/WRAM
	--     actually $2AAA is even, so it'll only affect mirroring which is ideal
	-- DATA writes can occur at $8000-9FFF, but care must be taken to maintain banking.
	--     Setting $8000 to a CHR bank prevents DATA writes from changing PRG banks
	--     The DATA write will change the bank select if it's written to an even address though
	--     To cover this, simply select the CHR bank again with $8000 reg after the data write
	--     Those DATA writes can also corrupt the PRG/CHR modes, so just always follow
	--     DATA writes by writing 0x00 to $8000

	-- $5555 commands written to $D555 (default due to mode 0)
	-- $2AAA commands written to $AAAA
	dict.nes("NES_CPU_WR", 0x8000, 0x07)
	dict.nes("NES_CPU_WR", 0x8001, 0x01)  -- 8KB @ CPU $A000

	-- DATA writes written to $8000-9FFF
	dict.nes("NES_CPU_WR", 0x8000, 0x06)
	dict.nes("NES_CPU_WR", 0x8001, 0x00)  -- 8KB @ CPU $8000

	-- Set $8000 bank select register to a CHR reg so $8000/1 writes don't change the PRG bank
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
end


-- Test the mapper's mirroring modes to verify working properly
-- Can be used to help identify board: returns true if pass, false if failed
local function mirror_test(debug)
	-- Put MMC3 in known state (mirror bits cleared)
	init_mapper()

	-- M = 0: Vertical
	if (nes.detect_mapper_mirroring(true) ~= "VERT") then
		print(mapname, "vert mirror test fail")
		return false
	end

	-- M = 1: Horizontal
	dict.nes("NES_CPU_WR", 0xA000, 0x01)  -- bit0 0-vert 1-horiz
	if (nes.detect_mapper_mirroring(true) ~= "HORZ") then
		print(mapname, "horz mirror test fail")
		return false
	end

	-- Reset back to vertical mirroring for consistency
	dict.nes("NES_CPU_WR", 0xA000, 0x00)  -- bit0 0-vert 1-horiz

	-- Passed all tests
	if (debug) then print(mapname, "mirror test passed") end
	return true
end

-- Read PRG-ROM flash ID
local function prgrom_manf_id(debug)
	init_mapper()

	if debug then print("reading PRG-ROM manf ID") end
	-- A0-A14 are all directly addressable in CNROM mode
	-- and mapper writes don't affect PRG banking
	dict.nes("NES_CPU_WR", 0xD555, 0xAA)
	dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
	dict.nes("NES_CPU_WR", 0xD555, 0x90)
	local rv = dict.nes("NES_CPU_RD", 0x8000)
	if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end
	rv = dict.nes("NES_CPU_RD", 0x8001)
	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end

	-- Exit software ID mode
	dict.nes("NES_CPU_WR", 0x8000, 0xF0)
end

-- Read CHR-ROM flash ID
local function chrrom_manf_id(debug)
	init_mapper()

	if debug then print("reading CHR-ROM manf ID") end
	-- A0-A14 are all directly addressable in CNROM mode
	-- and mapper writes don't affect PRG banking
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x1AAA, 0x55)
	dict.nes("NES_PPU_WR", 0x1555, 0x90)
	local rv = dict.nes("NES_PPU_RD", 0x0000)
	if debug then print("attempted read CHR-ROM manf ID:", string.format("%X", rv)) end
	rv = dict.nes("NES_PPU_RD", 0x0001)
	if debug then print("attempted read CHR-ROM prod ID:", string.format("%X", rv)) end

	-- Exit software ID mode
	dict.nes("NES_PPU_WR", 0x8000, 0xF0)
end


-- Dump the PRG ROM
local function dump_prgrom(file, rom_size_KB, debug)
	-- PRG-ROM dump 16KB at a time through MMC3 reg6&7 in mode 0
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x08  -- $8000
	-- TODO: update to NES_CPU_PAGE instead of NES_CPU_4KB

	while (read_count < num_reads) do
		if debug then print("dump PRG part", read_count, "of", num_reads) end

		-- Select desired bank(s) to dump
		dict.nes("NES_CPU_WR", 0x8000, 0x06)
		-- The bank is half the size of KB per read so must multiply by 2
		dict.nes("NES_CPU_WR", 0x8001, read_count * 2)  -- 8KB @ CPU $8000

		dict.nes("NES_CPU_WR", 0x8000, 0x07)
		-- The bank is half the size of KB per read so must multiply by 2 and add 1 for second 8KB
		dict.nes("NES_CPU_WR", 0x8001, read_count * 2 + 1)  -- 8KB @ CPU $A000

		-- 16 = number of KB to dump per loop
		-- 0x08 = starting read address A12-15 -> $8000
		-- NESCPU_4KB designate mapper independent read of NES CPU address space
		-- mapper must be 0-15 to designate A12-15
		dump.dumptofile(file, KB_per_read, addr_base, "NESCPU_4KB", false)

		read_count = read_count + 1
	end
end

-- Dump the PRG ROM (custom approach for Mega Man 3 and Astyanax)
local function dump_prgrom_custom(file, rom_size_KB, debug)
	-- PRG-ROM dump 16KB at a time through MMC3 reg6&7 in mode 0
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	while (read_count < num_reads) do
		if debug then print("dump PRG part", read_count, "of", num_reads) end

		-- Select desired bank(s) to dump
		dict.nes("NES_CPU_WR", 0x8000, 0x06)
		-- The bank is half the size of KB per read so must multiply by 2
		dict.nes("NES_CPU_WR", 0x8001, read_count * 2)  -- 8KB @ CPU $8000
		if debug then print("DEBUG: Set bank 6 to", read_count * 2, "for $8000-$9FFF") end

		dict.nes("NES_CPU_WR", 0x8000, 0x07)
		-- The bank is half the size of KB per read so must multiply by 2 and add 1 for second 8KB
		dict.nes("NES_CPU_WR", 0x8001, read_count * 2 + 1)  -- 8KB @ CPU $A000
		if debug then print("DEBUG: Set bank 7 to", read_count * 2 + 1, "for $A000-$BFFF") end

		-- Verify bank selection by reading a few bytes
		if debug then
			local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
			local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
			print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))
		end

		-- Use the standard dump method instead of direct memory reading
		-- This should work better for Super Mario 3
		dump.dumptofile(file, KB_per_read, 0x08, "NESCPU_4KB", false)

		read_count = read_count + 1
	end
end

-- Dump the CHR ROM
local function dump_chrrom(file, rom_size_KB, debug)
	local KB_per_read = 4  -- Dump one PT at a time so only need 2 reg writes
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00  -- $0000

	while (read_count < num_reads) do
		if debug then print("dump CHR part", read_count, "of", num_reads) end
		-- Set up only the 2KB CHR banks for dumping (like original MMC3)
		-- For 2KB CHR banks, bit 0 is not used, so shift left by 1
		dict.nes("NES_CPU_WR", 0x8000, 0x00)
		dict.nes("NES_CPU_WR", 0x8001, ((read_count * 2) << 1))  -- 2KB @ PPU $0000

		dict.nes("NES_CPU_WR", 0x8000, 0x01)
		dict.nes("NES_CPU_WR", 0x8001, ((read_count * 2 + 1) << 1))  -- 2KB @ PPU $0800

		-- 4 = number of KB to dump per loop
		-- 0x00 = starting read address A10-13 -> $0000
		-- mapper must be 0x00 or 0x04-0x3C to designate A10-13
		--     bits 7, 6, 1, & 0 CAN NOT BE SET!
		--     0x04 would designate that A10 is set -> $0400 (the second 1KB PT bank)
		--     0x20 would designate that A13 is set -> $2000 (first name table)
		dump.dumptofile(file, KB_per_read, addr_base, "NESPPU_1KB", false)

		read_count = read_count + 1
	end
end


-- Dump the WRAM, assumes the WRAM was enabled/disabled as desired prior to calling
local function dump_wram(file, rom_size_KB, debug)
	local KB_per_read = 8
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x06  -- $6000

	while (read_count < num_reads) do
		if debug then print("dump WRAM part", read_count, "of", num_reads) end

		dump.dumptofile(file, KB_per_read, addr_base, "NESCPU_4KB", false)

		read_count = read_count + 1
	end
end


-- Write a single byte to PRG-ROM flash
-- PRE: assumes mapper is initialized and bank is selected as prescribed in mapper_init
-- REQ: addr must be in the first bank $8000-9FFF
local function wr_prg_flash_byte(addr, value, debug)
	if (addr < 0x8000 or addr > 0x9FFF) then
		print("\n  ERROR! flash write to PRG-ROM", string.format("$%X", addr), "must be $8000-9FFF \n\n")
		return
	end

	-- Send unlock command and write byte
	dict.nes("NES_CPU_WR", 0xD555, 0xAA)
	dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
	dict.nes("NES_CPU_WR", 0xD555, 0xA0)
	dict.nes("NES_CPU_WR", addr, value)

	-- Recover by setting $8000 reg select back to a CHR reg
	dict.nes("NES_CPU_WR", 0x8000, 0x00)

	local rv = dict.nes("NES_CPU_RD", addr)
	local i = 0

	while (rv ~= value) do
		rv = dict.nes("NES_CPU_RD", addr)
		i = i + 1
	end
	if debug then print(i, "naks, done writing byte.") end
end

-- Write a single byte to CHR-ROM flash
-- PRE: assumes mapper is initialized and bank is selected as prescribed in mapper_init
-- REQ: addr must be in the first 2 banks $0000-0FFF
local function wr_chr_flash_byte(addr, value, debug)
	if (addr < 0x0000 or addr > 0x0FFF) then
		print("\n  ERROR! flash write to CHR-ROM", string.format("$%X", addr), "must be $0000-0FFF \n\n")
		return
	end

	-- Send unlock command and write byte
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x1AAA, 0x55)
	dict.nes("NES_PPU_WR", 0x1555, 0xA0)
	dict.nes("NES_PPU_WR", addr, value)

	local rv = dict.nes("NES_PPU_RD", addr)
	local i = 0

	while (rv ~= value) do
		rv = dict.nes("NES_PPU_RD", addr)
		i = i + 1
	end
	if debug then print(i, "naks, done writing byte.") end
end


-- Host flash one bank at a time
-- This is controlled from the host side one bank at a time
-- but requires mapper specific firmware flashing functions
local function flash_prgrom(file, rom_size_KB, debug)
	init_mapper()

	print("\nProgramming PRG-ROM flash")
	-- Initial testing of MMC3 with no specific MMC3 flash firmware functions 6min per 256KB = 0.7KBps

	local bank_size = 8 * 1024  -- MMC3 8KB per PRG bank
	local cur_bank = 0
	local total_banks = rom_size_KB * 1024 / bank_size

	while cur_bank < total_banks do
		if (cur_bank % 8 == 0) then
			print("writing PRG bank:", cur_bank, "of", total_banks - 1)
		end

		-- Write the current bank to the mapper register
		-- DATA writes written to $8000-9FFF
		dict.nes("NES_CPU_WR", 0x8000, 0x06)
		dict.nes("NES_CPU_WR", 0x8001, cur_bank)  -- 8KB @ CPU $8000

		-- Set $8000 bank select back to a CHR register
		-- Keeps from having the PRG bank changing when writing data
		dict.nes("NES_CPU_WR", 0x8000, 0x00)

		-- Have the device write a bank's worth of data
		-- FAST! 13sec for 512KB = 39KBps
		flash.write_file(file, bank_size / 1024, mapname, "PRGROM", false)

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")
end


-- Slow host flash one byte at a time
-- This is controlled from the host side byte by byte making it slow
-- but doesn't require specific firmware MMC3 flashing functions
local function flash_chrrom(file, rom_size_KB, debug)
	init_mapper()
	
	print("\nProgramming CHR-ROM flash")

	local bank_size = 4 * 1024  -- MMC3 2KB per lower CHR bank and we're using 2 of them
	local cur_bank = 0
	local total_banks = rom_size_KB * 1024 / bank_size

	while cur_bank < total_banks do
		if (cur_bank % 8 == 0) then
			print("writing CHR bank:", cur_bank, "of", total_banks - 1)
		end

		-- Write the current bank to the mapper register
		-- DATA writes written to $0000-0FFF
		dict.nes("NES_CPU_WR", 0x8000, 0x00)
		dict.nes("NES_CPU_WR", 0x8001, (cur_bank * 2) << 1)  -- 2KB @ PPU $0000
		dict.nes("NES_CPU_WR", 0x8000, 0x01)
		dict.nes("NES_CPU_WR", 0x8001, (cur_bank * 2 + 1) << 1)  -- 2KB @ PPU $0800

		-- Have the device write a "bank's" worth of data, actually 2x banks of 2KB each
		-- FAST! 13sec for 512KB = 39KBps
		flash.write_file(file, 4, mapname, "CHRROM", false)

		cur_bank = cur_bank + 1
	end

	print("Done Programming CHR-ROM flash")
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
	-- MMC3 has RAM capability present in some carts
	local dumpram = process_opts["dumpram"]
	local ramdumpfile = process_opts["dumpram_filename"]
	local writeram = process_opts["writeram"]
	local ramwritefile = process_opts["writeram_filename"]

	local rv = nil
	local file
	local prg_size = console_opts["prg_rom_size_kb"]
	local chr_size = console_opts["chr_rom_size_kb"]
	local wram_size = console_opts["wram_size_kb"]

	local filetype = "nes"

	-- Initialize device I/O for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

	-- Test cart by reading manufacturer/product ID
	if test then
		print("Testing", mapname)

		-- Verify mirroring is behaving as expected
		mirror_test(true)

		nes.ppu_ram_sense(0x1000, true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))

		-- Attempt to read PRG-ROM flash ID
		prgrom_manf_id(true)
		-- Attempt to read CHR-ROM flash ID
		chrrom_manf_id(true)
	end

	-- Dump the RAM to file
	if dumpram then
		print("\nDumping WRAM...")

		init_mapper()
		
		-- Maintain write protection, but allow reads
		dict.nes("NES_CPU_WR", 0xA001, 0xC0)

		file = assert(io.open(ramdumpfile, "wb"))

		-- Dump cart into file
		dump_wram(file, wram_size, false)

		-- For save data safety disable WRAM, and deny writes
		dict.nes("NES_CPU_WR", 0xA001, 0x40)

		-- Close file
		assert(file:close())

		print("DONE Dumping WRAM")
	end

	-- Dump the cart to dumpfile
	if read then
		print("\nDumping PRG & CHR ROMs...")

		-- Detect game type and use appropriate approach
		local game_type = detect_game_type()
		
		if game_type == "standard" then
			-- Standard approach: Use standard functions
			print("DEBUG: Using standard approach")
			init_mapper()
			
			file = assert(io.open(dumpfile, "wb"))
			
			-- Use standard header creation
			nes.write_header(file, prg_size, chr_size, 4, 0)
			
			-- Use standard dump functions
			dump_prgrom(file, prg_size, false)
			dump_chrrom(file, chr_size, false)
			
		elseif game_type == "custom" then
			-- Custom approach: Use custom functions
			print("DEBUG: Using custom approach")
			init_mapper_dump()
			
			file = assert(io.open(dumpfile, "wb"))
			
			-- Use custom header creation
			create_header(file, prg_size, chr_size)
			
			-- Use custom dump functions
			dump_prgrom_custom(file, prg_size, false)
			dump_chrrom(file, chr_size, false)
			
		else
			-- Hybrid approach: Use standard init with standard header and dump
			print("DEBUG: Using hybrid approach")
			init_mapper()  -- Use standard initialization
			
			file = assert(io.open(dumpfile, "wb"))
			
			-- Use standard header creation
			nes.write_header(file, prg_size, chr_size, 4, 0)
			
			-- Use standard dump functions
			dump_prgrom(file, prg_size, false)
			dump_chrrom(file, chr_size, false)
		end

		-- Close file
		assert(file:close())

		print("DONE Dumping PRG & CHR ROMs")
	end


	-- Erase the cart
	if erase then
		print("\nerasing", mapname)

		init_mapper()

		print("erasing PRG-ROM")
		dict.nes("NES_CPU_WR", 0xD555, 0xAA)
		dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xD555, 0x80)
		dict.nes("NES_CPU_WR", 0xD555, 0xAA)
		dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xD555, 0x10)
		rv = dict.nes("NES_CPU_RD", 0x8000)

		local i = 0
		while (rv ~= 0xFF) do
			rv = dict.nes("NES_CPU_RD", 0x8000)
			i = i + 1
		end
		print(i, "naks, done erasing prg.")

		-- TODO: erase CHR-ROM only if present
		init_mapper()

		print("erasing CHR-ROM")
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_PPU_WR", 0x1AAA, 0x55)
		dict.nes("NES_PPU_WR", 0x1555, 0x80)
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_PPU_WR", 0x1AAA, 0x55)
		dict.nes("NES_PPU_WR", 0x1555, 0x10)
		rv = dict.nes("NES_PPU_RD", 0x0000)

		i = 0
		while (rv ~= 0xFF) do
			rv = dict.nes("NES_PPU_RD", 0x0000)
			i = i + 1
		end
		print(i, "naks, done erasing chr.")
	end

	-- Write to WRAM on the cart
	if writeram then
		print("\nWriting to WRAM...")

		init_mapper()
		
		-- Disable write protection, and enable WRAM
		dict.nes("NES_CPU_WR", 0xA001, 0x80)

		file = assert(io.open(ramwritefile, "rb"))

		flash.write_file(file, wram_size, "NOVAR", "PRGRAM", false)

		-- For save data safety disable WRAM, and deny writes
		dict.nes("NES_CPU_WR", 0xA001, 0x40)

		-- Close file
		assert(file:close())

		print("DONE Writing WRAM")
	end

	-- Program flashfile to the cart
	if program then
		file = assert(io.open(flashfile, "rb"))
		-- Determine if auto-doubling, deinterleaving, etc. needs done to make board compatible with ROM

		if filetype == "nes" then
			-- Advance past the 16-byte header
			-- TODO: set mirroring bit via ciccom
			local buffsize = 1
			local byte
			local count = 1

			for byte in file:lines(buffsize) do
				local data = string.unpack("B", byte, 1)
				count = count + 1
				if count == 17 then break end
			end
		end

		flash_prgrom(file, prg_size, true)
		flash_chrrom(file, chr_size, true)

		-- Close file
		assert(file:close())
	end

	-- Verify flashfile is on the cart
	if verify then
		print("\nPost dumping PRG & CHR ROMs...")

		init_mapper()

		file = assert(io.open(verifyfile, "wb"))

		-- Create header: pass open & empty file & ROM sizes
		create_header(file, prg_size, chr_size)

		-- Dump cart into file
		time.start()
		dump_prgrom(file, prg_size, false)
		dump_chrrom(file, chr_size, false)
		time.report(prg_size + chr_size)

		-- Close file
		assert(file:close())

		-- Compare the flash file vs post dump file
		if (files.compare(verifyfile, flashfile, true)) then
			print("\nSUCCESS! Flash verified")
		else
			print("\n\n\nFAILURE! Flash verification did not match")
		end
	end

	dict.io("IO_RESET")
end

-- Functions other modules are able to call
mmc3.process = process

-- Return the module's table
return mmc3
