-- MMC1 mapper for INL Retro
-- Supports iNES mapper 1 (MMC1)

local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"

local mmc1 = {}

-- File constants
local mapname = "MMC1"

-- local functions

local function create_header(file, prgKB, chrKB)
	nes.write_header(file, prgKB, chrKB, dict.op_buffer[mapname], 0)
end


local function init_mapper(debug)
	-- MMC1 ignores all but the first write
	dict.nes("NES_CPU_RD", 0x8000)
	-- Reset MMC1 shift register with D7 set
	dict.nes("NES_CPU_WR", 0x8000, 0x80)
	-- This reset also effectively sets the control reg to 0x0C:
	--     prg mode 3: last 16KB fixed
	--     chr mode 0: single 8KB bank
	--     mirroring 0: 1 screen NT0

	-- 32KB mode, prg bank @ $8000-FFFF, 4KB CHR mode
	dict.nes("NES_MMC1_WR", 0x8000, 0x10)
	-- Note: the mapper will constantly reset to this when writing to PRG-ROM
	-- PRG-ROM A18-A14

	-- Select first PRG-ROM bank, disable save RAM
	dict.nes("NES_MMC1_WR", 0xE000, 0x10)  -- LSBit ignored in 32KB mode
	                                       -- bit4 RAM enable 0-enabled 1-disabled

	-- CHR-ROM A16-12 (A14-12 are required to be valid)
	-- bit4 (CHR A16) is /CE pin for WRAM on SNROM
	dict.nes("NES_MMC1_WR", 0xA000, 0x12)  -- 4KB bank @ PT0  $2AAA cmd and writes
	dict.nes("NES_MMC1_WR", 0xC000, 0x15)  -- 4KB bank @ PT1  $5555 cmd fixed

	-- Add test read to verify standard initialization
	if debug then
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j + 1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		print("DEBUG: Standard init test reads $8000-$800F:")
		local byte_str = ""
		for j = 1, 16 do
			byte_str = byte_str .. string.format("%02X ", test_bytes[j])
		end
		print("  " .. byte_str)
	end
end



-- Test the mapper's mirroring modes to verify working properly
-- Can be used to help identify board: returns true if pass, false if failed
local function mirror_test(debug)
	-- Put MMC1 in known state (mirror bits cleared)
	init_mapper()

	-- MM = 0: 1 screen A
	dict.nes("NES_MMC1_WR", 0x8000, 0x00)
	if (nes.detect_mapper_mirroring() ~= "1SCNA") then
		print("MMC1 mirror test fail (1 screen A)")
		return false
	end

	-- MM = 1: 1 screen B
	dict.nes("NES_MMC1_WR", 0x8000, 0x01)
	if (nes.detect_mapper_mirroring() ~= "1SCNB") then
		print("MMC1 mirror test fail (1 screen B)")
		return false
	end

	-- MM = 2: Vertical
	dict.nes("NES_MMC1_WR", 0x8000, 0x02)
	if (nes.detect_mapper_mirroring() ~= "VERT") then
		print("MMC1 mirror test fail (Vertical)")
		return false
	end

	-- MM = 3: Horizontal
	dict.nes("NES_MMC1_WR", 0x8000, 0x03)
	if (nes.detect_mapper_mirroring() ~= "HORZ") then
		print("MMC1 mirror test fail (Horizontal)")
		return false
	end

	-- Passed all tests
	if (debug) then print("MMC1 mirror test passed") end
	return true
end


local function wr_flash_byte(addr, value, debug)

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
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
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
	-- PRG-ROM dump 32KB at a time in 32KB bank mode
	local KB_per_read = 32
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x08  -- $8000

	while (read_count < num_reads) do
		if debug then print("dump PRG part", read_count, "of", num_reads) end

		-- Select desired bank(s) to dump
		dict.nes("NES_MMC1_WR", 0xE000, read_count << 1)  -- LSBit ignored in 32KB mode

		-- 32 = number of KB to dump per loop
		-- 0x08 = starting read address A12-15 -> $8000
		-- NESCPU_4KB designate mapper independent read of NES CPU address space
		-- mapper must be 0-15 to designate A12-15
		dump.dumptofile(file, KB_per_read, addr_base, "NESCPU_4KB", false)

		read_count = read_count + 1
	end
end

-- Compatibility PRG dumper for picky MMC1 boards (mode 2: switchable @$C000)
local function dump_prgrom_mode2(file, rom_size_KB, debug)
	-- PRG-ROM dump 16KB at a time with $C000 switchable window
	local KB_per_read = 16
	local num_reads = rom_size_KB // 16
	local addr_fixed_8000 = 0x08 -- $8000 fixed (bank 0 in mode 2)
	local addr_sw_C000    = 0x0C -- $C000 switchable

	print("DEBUG: Starting mode 2 dump for", rom_size_KB, "KB ROM")

	-- control = 0x08 => PRG mode 2 (H mirror)
	dict.nes("NES_MMC1_WR", 0x8000, 0x08)
	dict.nes("NES_CPU_RD", 0x8000); dict.nes("NES_CPU_RD", 0xC000)
	
	-- Test read to verify mode 2 is working
	local test1 = dict.nes("NES_CPU_RD", 0x8000)
	local test2 = dict.nes("NES_CPU_RD", 0xC000)
	if debug then 
		print("DEBUG: Mode 2 initial test reads:", string.format("$8000=0x%02X $C000=0x%02X", test1, test2))
		
		-- Also test a range of bytes to see the pattern
		print("DEBUG: Mode 2 initial $8000-$800F:")
		local byte_str = ""
		for j = 0, 15 do
			local byte = dict.nes("NES_CPU_RD", 0x8000 + j)
			byte_str = byte_str .. string.format("%02X ", byte)
		end
		print("  " .. byte_str)
		
		print("DEBUG: Mode 2 initial $C000-$C00F:")
		byte_str = ""
		for j = 0, 15 do
			local byte = dict.nes("NES_CPU_RD", 0xC000 + j)
			byte_str = byte_str .. string.format("%02X ", byte)
		end
		print("  " .. byte_str)
	end

	-- banks 1..N-1 via $C000
	for i = 1, (num_reads - 1) do
		if debug then print("[MMC1] (mode2) bank ", i, " / ", (num_reads-1)) end
		dict.nes("NES_MMC1_WR", 0xE000, i)
		dict.nes("NES_CPU_RD", 0x8000); dict.nes("NES_CPU_RD", 0xC000)
		
		-- Test read multiple bytes to verify bank selection and data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0xC000 + j)
		end
		if debug then 
			print("DEBUG: Bank", i, "test reads $C000-$C00F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end
		
		dump.dumptofile(file, KB_per_read, addr_sw_C000, "NESCPU_4KB", false)
	end

	-- fixed first bank once from $8000
	if debug then print("[MMC1] (mode2) fixed bank 0 @ $8000") end
	dict.nes("NES_CPU_RD", 0x8000)
	
	-- Test read multiple bytes to verify fixed bank data
	local test_bytes = {}
	for j = 0, 15 do
		test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
	end
	if debug then 
		print("DEBUG: Fixed bank 0 test reads $8000-$800F:")
		local byte_str = ""
		for j = 1, 16 do
			byte_str = byte_str .. string.format("%02X ", test_bytes[j])
		end
		print("  " .. byte_str)
	end
	
	dump.dumptofile(file, KB_per_read, addr_fixed_8000, "NESCPU_4KB", false)
	
	print("DEBUG: Mode 2 dump completed")
end

-- Direct memory reading approach for very problematic MMC1 carts
local function dump_prgrom_direct(file, rom_size_KB, debug)
	-- PRG-ROM dump 32KB at a time using direct memory reading
	local KB_per_read = 32
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting direct memory dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		--select desired bank(s) to dump
		dict.nes("NES_MMC1_WR", 0xE000, read_count<<1)	--LSBit ignored in 32KB mode
		
		-- Add a small delay and verify bank selection
		dict.nes("NES_CPU_RD", 0x8000)
		dict.nes("NES_CPU_RD", 0x8000)
		
		-- Test read multiple bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Read 32KB directly from $8000-$FFFF
		for i = 0, 32767 do
			local byte = dict.nes("NES_CPU_RD", 0x8000 + i)
			file:write(string.char(byte))
		end

		read_count = read_count + 1
	end
	
	print("DEBUG: Direct memory dump completed")
end

-- MMC3-style custom dumping approach for problematic carts
local function dump_prgrom_mmc3_style(file, rom_size_KB, debug)
	-- PRG-ROM dump 16KB at a time using MMC3-style approach
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting MMC3-style dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- MMC3-style bank selection with detailed debug output
		-- For MMC1, we'll use 16KB banks instead of 8KB
		dict.nes("NES_MMC1_WR", 0xE000, read_count)	-- Select bank
		print("DEBUG: Set bank", read_count, "for $8000-$BFFF")

		-- Verify bank selection by reading test bytes (MMC3 style)
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Use dump.dumptofile like MMC3 does, but with different address base
		-- Try using address base 0x00 like MMC3 custom approach
		dump.dumptofile( file, KB_per_read, 0x00, "NESCPU_4KB", false )

		read_count = read_count + 1
	end
	
	print("DEBUG: MMC3-style dump completed")
end

-- Standard dumping approach for Battle of Olympus with custom initialization
local function dump_prgrom_standard(file, rom_size_KB, debug)
	-- PRG-ROM dump 16KB at a time using standard approach
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting standard dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- Standard bank selection
		dict.nes("NES_MMC1_WR", 0xE000, read_count)	-- Select bank
		print("DEBUG: Set bank", read_count, "for $8000-$BFFF")

		-- Verify bank selection by reading test bytes
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Use standard dump.dumptofile with address base 0x08
		dump.dumptofile( file, KB_per_read, 0x08, "NESCPU_4KB", false )

		read_count = read_count + 1
	end
	
	print("DEBUG: Standard dump completed")
end

-- No initialization dumping approach - read PRG-ROM as-is
local function dump_prgrom_no_init(file, rom_size_KB, debug)
	-- PRG-ROM dump without any mapper initialization
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting no-init dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- Try to select bank without full initialization
		dict.nes("NES_MMC1_WR", 0xE000, read_count)	-- Select bank
		print("DEBUG: Set bank", read_count, "for $8000-$BFFF (no init)")

		-- Verify bank selection by reading test bytes
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Use dump.dumptofile with address base 0x08
		dump.dumptofile( file, KB_per_read, 0x08, "NESCPU_4KB", false )

		read_count = read_count + 1
	end
	
	print("DEBUG: No-init dump completed")
end

-- Minimal initialization dumping approach
local function dump_prgrom_minimal(file, rom_size_KB, debug)
	-- PRG-ROM dump with minimal mapper initialization
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting minimal dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- Select bank with minimal setup
		dict.nes("NES_MMC1_WR", 0xE000, read_count)	-- Select bank
		print("DEBUG: Set bank", read_count, "for $8000-$BFFF (minimal)")

		-- Verify bank selection by reading test bytes
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Use dump.dumptofile with address base 0x08
		dump.dumptofile( file, KB_per_read, 0x08, "NESCPU_4KB", false )

		read_count = read_count + 1
	end
	
	print("DEBUG: Minimal dump completed")
end

-- GitHub MMC1 style dumping approach
local function dump_prgrom_github_style(file, rom_size_KB, debug)
	-- PRG-ROM dump using GitHub MMC1 approach
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting GitHub MMC1 style dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- GitHub style bank selection - use the exact sequence from GitHub
		dict.nes("NES_MMC1_WR", 0xE000, read_count)	-- Select bank
		print("DEBUG: Set bank", read_count, "for $8000-$BFFF (GitHub style)")

		-- Verify bank selection by reading test bytes
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Use dump.dumptofile with address base 0x08 (standard approach)
		dump.dumptofile( file, KB_per_read, 0x08, "NESCPU_4KB", false )

		read_count = read_count + 1
	end
	
	print("DEBUG: GitHub MMC1 style dump completed")
end

-- Kevtris MMC1 style dumping approach
local function dump_prgrom_kevtris_style(file, rom_size_KB, debug)
	-- PRG-ROM dump using Kevtris MMC1 approach
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting Kevtris MMC1 style dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- Kevtris style bank selection - use proper MMC1 serial interface
		-- According to Kevtris: only the LAST WRITE matters for which register gets loaded
		-- We want to load register 3 (PRG ROM bank register)
		dict.nes("NES_MMC1_WR", 0xE000, read_count)	-- Select bank
		print("DEBUG: Set bank", read_count, "for $8000-$BFFF (Kevtris style)")

		-- Verify bank selection by reading test bytes
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Use dump.dumptofile with address base 0x08 (standard approach)
		dump.dumptofile( file, KB_per_read, 0x08, "NESCPU_4KB", false )

		read_count = read_count + 1
	end
	
	print("DEBUG: Kevtris MMC1 style dump completed")
end

-- emudev MMC1 style dumping approach
local function dump_prgrom_emudev_style(file, rom_size_KB, debug)
	-- PRG-ROM dump using emudev MMC1 approach
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting emudev MMC1 style dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- emudev style bank selection - use proper 5-write sequence for each bank
		-- Convert bank number to 5-bit value and write each bit
		local bank_value = read_count
		print("DEBUG: Setting bank", read_count, "using 5-write sequence (emudev style)")
		
		-- Write bank value using proper 5-write sequence
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 0
		dict.nes("NES_MMC1_WR", 0xE000, (bank_value >> 1) & 0x01) -- Write bit 1
		dict.nes("NES_MMC1_WR", 0xE000, (bank_value >> 2) & 0x01) -- Write bit 2
		dict.nes("NES_MMC1_WR", 0xE000, (bank_value >> 3) & 0x01) -- Write bit 3
		dict.nes("NES_MMC1_WR", 0xE000, (bank_value >> 4) & 0x01) -- Write bit 4

		-- Verify bank selection by reading test bytes
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Use dump.dumptofile with address base 0x08 (standard approach)
		dump.dumptofile( file, KB_per_read, 0x08, "NESCPU_4KB", false )

		read_count = read_count + 1
	end
	
	print("DEBUG: emudev MMC1 style dump completed")
end

-- NESdev MMC1 style dumping approach
local function dump_prgrom_nesdev_style(file, rom_size_KB, debug)
	-- PRG-ROM dump using NESdev MMC1 approach
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting NESdev MMC1 style dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- NESdev style bank selection - use proper 5-write sequence for each bank
		-- Based on NESdev documentation: "Only on the fifth write does the address matter"
		local bank_value = read_count
		print("DEBUG: Setting bank", read_count, "using NESdev 5-write sequence")
		
		-- Write bank value using NESdev 5-write sequence
		-- According to NESdev: "the CPU writes five times with bit 7 clear and one bit of the desired value in bit 0"
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 0
		dict.nes("NES_MMC1_WR", 0xE000, (bank_value >> 1) & 0x01) -- Write bit 1
		dict.nes("NES_MMC1_WR", 0xE000, (bank_value >> 2) & 0x01) -- Write bit 2
		dict.nes("NES_MMC1_WR", 0xE000, (bank_value >> 3) & 0x01) -- Write bit 3
		dict.nes("NES_MMC1_WR", 0xE000, (bank_value >> 4) & 0x01) -- Write bit 4 (5th write - address matters)

		-- Verify bank selection by reading test bytes
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Use dump.dumptofile with address base 0x08 (standard approach)
		dump.dumptofile( file, KB_per_read, 0x08, "NESCPU_4KB", false )

		read_count = read_count + 1
	end
	
	print("DEBUG: NESdev MMC1 style dump completed")
end

-- Mario's Right Nut MMC1 style dumping approach
local function dump_prgrom_marios_right_nut_style(file, rom_size_KB, debug)
	-- PRG-ROM dump using Mario's Right Nut MMC1 approach
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting Mario's Right Nut MMC1 style dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- Mario's Right Nut style bank selection - use exact assembly code approach
		-- Based on Mario's Right Nut tutorial: use LSR A (Logical Shift Right) approach
		local bank_value = read_count
		print("DEBUG: Setting bank", read_count, "using Mario's Right Nut 5-write sequence")
		
		-- Write bank value using Mario's Right Nut 5-write sequence
		-- Mimics the exact assembly code: STA $E000, LSR A, STA $E000, etc.
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 0
		bank_value = bank_value >> 1
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 1
		bank_value = bank_value >> 1
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 2
		bank_value = bank_value >> 1
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 3
		bank_value = bank_value >> 1
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 4 (5th write)

		-- Verify bank selection by reading test bytes
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Use dump.dumptofile with address base 0x08 (standard approach)
		dump.dumptofile( file, KB_per_read, 0x08, "NESCPU_4KB", false )

		read_count = read_count + 1
	end
	
	print("DEBUG: Mario's Right Nut MMC1 style dump completed")
end

-- Mouse Bite Labs MMC1 style dumping approach
local function dump_prgrom_mouse_bite_labs_style(file, rom_size_KB, debug)
	-- PRG-ROM dump using Mouse Bite Labs MMC1 approach
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting Mouse Bite Labs MMC1 style dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- Mouse Bite Labs style bank selection - use hardware-specific approach
		-- Based on Mouse Bite Labs reproduction board guide: try different board configurations
		local bank_value = read_count
		print("DEBUG: Setting bank", read_count, "using Mouse Bite Labs 5-write sequence")
		
		-- Write bank value using Mouse Bite Labs 5-write sequence
		-- Based on reproduction board hardware requirements
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 0
		bank_value = bank_value >> 1
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 1
		bank_value = bank_value >> 1
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 2
		bank_value = bank_value >> 1
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 3
		bank_value = bank_value >> 1
		dict.nes("NES_MMC1_WR", 0xE000, bank_value & 0x01) -- Write bit 4 (5th write)

		-- Verify bank selection by reading test bytes
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Use dump.dumptofile with address base 0x08 (standard approach)
		dump.dumptofile( file, KB_per_read, 0x08, "NESCPU_4KB", false )

		read_count = read_count + 1
	end
	
	print("DEBUG: Mouse Bite Labs MMC1 style dump completed")
end

-- Manual byte-by-byte dumping approach (bypasses dump.dumptofile)
local function dump_prgrom_manual(file, rom_size_KB, debug)
	-- PRG-ROM dump using manual byte-by-byte approach
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting manual byte-by-byte dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- Try different bank selection approaches
		print("DEBUG: Setting bank", read_count, "using manual approach")
		
		-- Try simple bank selection first
		dict.nes("NES_MMC1_WR", 0xE000, read_count)
		
		-- Verify bank selection by reading test bytes
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Manual byte-by-byte dump instead of using dump.dumptofile
		print("DEBUG: Writing", KB_per_read, "KB manually to file")
		for i = 0, (KB_per_read * 1024) - 1 do
			local byte = dict.nes("NES_CPU_RD", 0x8000 + i)
			file:write(string.char(byte))
		end
		print("DEBUG: Wrote", KB_per_read * 1024, "bytes to file")

		read_count = read_count + 1
	end
	
	print("DEBUG: Manual byte-by-byte dump completed")
end

-- Standard MMC1 style dumping approach (uses exact same init as working games)
local function dump_prgrom_standard_style(file, rom_size_KB, debug)
	-- PRG-ROM dump using standard MMC1 approach
	local KB_per_read = 32
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting standard MMC1 style dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- Standard bank selection - use exact same approach as working games
		print("DEBUG: Setting bank", read_count, "using standard approach")
		
		-- Use exact same bank selection as standard init: read_count<<1
		dict.nes("NES_MMC1_WR", 0xE000, read_count << 1)
		
		-- Verify bank selection by reading test bytes
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Use dump.dumptofile with address base 0x08 (standard approach)
		dump.dumptofile( file, KB_per_read, 0x08, "NESCPU_4KB", false )

		read_count = read_count + 1
	end
	
	print("DEBUG: Standard MMC1 style dump completed")
end

-- Power-on default state dumping approach (no initialization at all)
local function dump_prgrom_poweron_default(file, rom_size_KB, debug)
	-- PRG-ROM dump using power-on default state (no MMC1 initialization)
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting power-on default state dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- Don't do ANY bank selection - just read from power-on default state
		print("DEBUG: Reading bank", read_count, "in power-on default state (no bank selection)")
		
		-- Verify what we're reading
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Manual byte-by-byte dump from power-on default state
		print("DEBUG: Writing", KB_per_read, "KB from power-on default state")
		for i = 0, (KB_per_read * 1024) - 1 do
			local byte = dict.nes("NES_CPU_RD", 0x8000 + i)
			file:write(string.char(byte))
		end
		print("DEBUG: Wrote", KB_per_read * 1024, "bytes to file")

		read_count = read_count + 1
	end
	
	print("DEBUG: Power-on default state dump completed")
end

-- Real NES power-on sequence dumping approach (mimics actual NES boot)
local function dump_prgrom_real_nes_sequence(file, rom_size_KB, debug)
	-- PRG-ROM dump using real NES power-on sequence
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0

	print("DEBUG: Starting real NES power-on sequence dump for", rom_size_KB, "KB ROM")

	while ( read_count < num_reads ) do
		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		-- Try to mimic real NES behavior for each bank
		print("DEBUG: Reading bank", read_count, "using real NES sequence")
		
		-- Simulate real NES timing between operations
		for i = 1, 10 do
			dict.nes("NES_CPU_RD", 0x8000)
		end
		
		-- Try different address ranges that real NES might access
		local addresses = {0x8000, 0x8001, 0x8002, 0x8003, 0x8004, 0x8005, 0x8006, 0x8007}
		for _, addr in ipairs(addresses) do
			dict.nes("NES_CPU_RD", addr)
		end
		
		-- Verify what we're reading
		local test_byte1 = dict.nes("NES_CPU_RD", 0x8000)
		local test_byte2 = dict.nes("NES_CPU_RD", 0xA000)
		print("DEBUG: Read $8000=", string.format("0x%02X", test_byte1), "$A000=", string.format("0x%02X", test_byte2))

		-- Read a range of bytes to verify we're getting data
		local test_bytes = {}
		for j = 0, 15 do
			test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
		end
		if debug then 
			print("DEBUG: Bank", read_count, "test reads $8000-$800F:")
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
		end

		-- Manual byte-by-byte dump with real NES timing
		print("DEBUG: Writing", KB_per_read, "KB using real NES sequence")
		for i = 0, (KB_per_read * 1024) - 1 do
			local byte = dict.nes("NES_CPU_RD", 0x8000 + i)
			file:write(string.char(byte))
			
			-- Add small delays to mimic real NES timing
			if i % 1000 == 0 then
				for k = 1, 5 do
					dict.nes("NES_CPU_RD", 0x8000)
				end
			end
		end
		print("DEBUG: Wrote", KB_per_read * 1024, "bytes to file")

		read_count = read_count + 1
	end
	
	print("DEBUG: Real NES power-on sequence dump completed")
end

-- Game detection for problematic MMC1 carts
local function detect_mmc1_game_type()
	-- Do minimal setup to read from PRG ROM
	dict.nes("NES_CPU_RD", 0x8000)
	dict.nes("NES_CPU_WR", 0x8000, 0x80) -- reset MMC1 shift register
	dict.nes("NES_MMC1_WR", 0x8000, 0x10) -- 32KB mode
	dict.nes("NES_MMC1_WR", 0xE000, 0x10) -- select first bank
	
	-- Try to read some bytes from PRG ROM
	local byte1 = dict.nes("NES_CPU_RD", 0x8000)
	local byte2 = dict.nes("NES_CPU_RD", 0x8001)
	local byte3 = dict.nes("NES_CPU_RD", 0x8002)
	local byte4 = dict.nes("NES_CPU_RD", 0x8003)
	local byte5 = dict.nes("NES_CPU_RD", 0x8004)
	
	print("DEBUG: Read bytes:", string.format("0x%02X 0x%02X 0x%02X 0x%02X 0x%02X", byte1, byte2, byte3, byte4, byte5))
	
	-- Check for Battle of Olympus signature or problematic patterns
	if byte1 == 0xFF and byte2 == 0xFF and byte3 == 0xFF then
		print("DEBUG: Detected problematic cart (all 0xFF) - using mode 2 approach")
		return "mode2"
	end
	
	-- Check for other problematic patterns
	if byte1 == 0x00 and byte2 == 0x00 and byte3 == 0x00 then
		print("DEBUG: Detected problematic cart (all 0x00) - using mode 2 approach")
		return "mode2"
	end
	
	-- Check for Battle of Olympus specific patterns
	if byte1 == 0x4C and byte2 == 0x00 and byte3 == 0x80 then
		print("DEBUG: Detected Battle of Olympus pattern - using direct approach")
		return "direct"
	end
	
	-- Check for other known problematic patterns
	if byte1 == 0x20 and byte2 == 0x00 and byte3 == 0x80 then  -- JSR $8000
		print("DEBUG: Detected JSR pattern - using direct approach")
		return "direct"
	end
	
	-- Default to standard approach
	print("DEBUG: Using standard approach")
	return "standard"
end

-- Wrapper: try original PRG dumper; if it writes ~0 bytes, retry with mode 2
local function dump_prgrom_with_fallback(file, prg_kb, debug)
	local need = prg_kb * 1024
	local before = assert(file:seek("cur"))
	dump_prgrom(file, prg_kb, debug)
	local after = assert(file:seek("cur"))
	local wrote = after - before
	
	-- Check if we got valid data (not all 0xFF or 0x00)
	local file_pos = file:seek("cur")
	file:seek("set", before)
	local sample_bytes = {}
	for i = 1, math.min(1024, need) do
		local byte = file:read(1)
		if byte then
			sample_bytes[i] = string.byte(byte)
		end
	end
	file:seek("set", file_pos)
	
	-- Count 0xFF and 0x00 bytes in sample
	local ff_count = 0
	local zero_count = 0
	for _, byte in ipairs(sample_bytes) do
		if byte == 0xFF then ff_count = ff_count + 1
		elseif byte == 0x00 then zero_count = zero_count + 1
		end
	end
	
	local total_sample = #sample_bytes
	local ff_ratio = total_sample > 0 and (ff_count / total_sample) or 0
	local zero_ratio = total_sample > 0 and (zero_count / total_sample) or 0
	
	if wrote < need or ff_ratio > 0.9 or zero_ratio > 0.9 then
		if debug then 
			print(string.format("[MMC1] original PRG wrote %d (need %d), FF ratio: %.2f, Zero ratio: %.2f -> retrying in mode 2", 
				wrote, need, ff_ratio, zero_ratio)) 
		end
		assert(file:seek("set", 16)) -- back to after 16-byte header
		dump_prgrom_mode2(file, prg_kb, debug)
	else
		if debug then print(string.format("[MMC1] PRG OK via original (wrote %d)", wrote)) end
	end
end



-- Dump the CHR ROM
local function dump_chrrom(file, rom_size_KB, debug)
	local KB_per_read = 8  -- Dump both PT
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00  -- $0000

	while (read_count < num_reads) do
		if debug then print("dump CHR part", read_count, "of", num_reads) end

		dict.nes("NES_MMC1_WR", 0xA000, read_count * 2)  -- 4KB bank @ PT0  $2AAA cmd and writes
		dict.nes("NES_MMC1_WR", 0xC000, read_count * 2 + 1)  -- 4KB bank @ PT1  $5555 cmd fixed

		-- 8 = number of KB to dump per loop
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
	-- TODO: update to NES_CPU_PAGE instead of NES_CPU_4KB

	while (read_count < num_reads) do
		if debug then print("dump WRAM part", read_count, "of", num_reads) end

		dump.dumptofile(file, KB_per_read, addr_base, "NESCPU_4KB", false)

		read_count = read_count + 1
	end
end


--write a single byte to PRG-ROM flash
--PRE: assumes mapper is initialized and bank is selected as prescribed in mapper_init
--REQ: addr must be in the first bank $8000-FFFF
local function wr_prg_flash_byte(addr, value, bank, debug)

	if (addr < 0x8000 or addr > 0xFFFF) then
		print("\n  ERROR! flash write to PRG-ROM", string.format("$%X", addr), "must be $8000-FFFF \n\n")
		return
	end

--mmc1_wr(0x8000, 0x10, 0);               //32KB mode
--//IDK why, but somehow only the first byte gets programmed when ROM A14=1
--//so somehow it's getting out of 32KB mode for follow on bytes..
--//even though we reset to 32KB mode after the corrupting final write
--
--wr_func( unlock1, 0xAA );
--wr_func( unlock2, 0x55 );
--wr_func( unlock1, 0xA0 );
--wr_func( ((addrH<<8)| n), buff->data[n] );
--//writes to flash are to $8000-FFFF so any register could have been corrupted and shift register may be off
--//In reality MMC1 should have blocked all subsequent writes, so maybe only the CHR reg2 got corrupted..?                mmc1_wr(0x8000, 0x10, 1);               //32KB mode
--mmc1_wr(0xE000, bank, 0);       //reset shift register, and bank register

	--MMC1 ignores all but the first write
	--dict.nes("NES_CPU_RD", 0x8000)
--	dict.nes("NES_CPU_WR", 0x8000, 0x80) --reset MMC1 shift register with D7 set

	--dict.nes("NES_MMC1_WR", 0x8000, 0x10) --32KB mode, prg bank @ $8000-FFFF, 4KB CHR mode
	--doing this after the write doesn't work for some reason....
	--I think the reason this works is because the last instruction is a write (and it's valid)
	--so the next 4 writes are blocked by the MMC1 including the reset
	dict.nes("NES_MMC1_WR", 0xC000, 0x05)	--this seems to work as well which makes sense based on above..
	--so now all follow on writes will be blocked until there is a read

	--send unlock command and write byte
	dict.nes("NES_CPU_WR", 0xD555, 0xAA)	--this will reset the MMC1..?, 
						--but not if it was blocked by a previous write
	dict.nes("NES_CPU_WR", 0xAAAA, 0x55)	--blocked
	dict.nes("NES_CPU_WR", 0xD555, 0xA0)	--blocked
	dict.nes("NES_CPU_WR", addr, value)	--blocked

--	dict.nes("NES_CPU_RD", 0x8000)	--must read before resetting
--	dict.nes("NES_CPU_WR", 0x8000, 0x80) --reset MMC1 shift register with D7 set
--	dict.nes("NES_MMC1_WR", 0x8000, 0x10) --32KB mode, prg bank @ $8000-FFFF, 4KB CHR mode
--	dict.nes("NES_MMC1_WR", 0xE000, bank<<1) --32KB mode, prg bank @ $8000-FFFF, 4KB CHR mode

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
--REQ: addr must be in the first bank $0000-0FFF
local function wr_chr_flash_byte(addr, value, bank, debug)

	if (addr < 0x0000 or addr > 0x0FFF) then
		print("\n  ERROR! flash write to CHR-ROM", string.format("$%X", addr), "must be $0000-0FFF \n\n")
		return
	end

	--set banks for unlock commands
	dict.nes("NES_MMC1_WR", 0xA000, 0x02) --4KB bank @ PT0  $2AAA cmd and writes (always write data to PT0)
	--dict.nes("NES_MMC1_WR", 0xC000, 0x05) --4KB bank @ PT1  $5555 cmd fixed (never changed)

	--send unlock command and write byte
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
	dict.nes("NES_PPU_WR", 0x1555, 0xA0)

	--select desired bank for write
	dict.nes("NES_MMC1_WR", 0xA000, bank) --4KB bank @ PT0  $2AAA cmd and writes (always write data to PT0)
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


--host flash one bank at a time...
--this is controlled from the host side one bank at a time
--but requires mapper specific firmware flashing functions
--there is super slow version commented out that doesn't require mapper specific firmware code
local function flash_prgrom(file, rom_size_KB, debug)

	init_mapper()

	--test some bytes
	--wr_prg_flash_byte(0x0000, 0xA5, true)
	--wr_prg_flash_byte(0x0FFF, 0x5A, true)

	print("\nProgramming PRG-ROM flash")
	--initial testing of MMC3 with no specific MMC3 flash firmware functions 6min per 256KByte = 0.7KBps


	local base_addr = 0x8000 --writes occur $8000-9FFF
	local bank_size = 32*1024 --MMC1 32KByte bank mode
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata


	while cur_bank < total_banks do

		if (cur_bank % 2 == 0) then
			print("writing PRG bank:", cur_bank, "of", total_banks - 1)
		end

		-- Write the current bank to the mapper register
		dict.nes("NES_MMC1_WR", 0xE000, cur_bank << 1)  -- LSBit ignored in 32KB mode

		--program the entire bank's worth of data

		--[[  This version of the code programs a single byte at a time but doesn't require 
		--	mapper specific functions in the firmware
		print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware mapper specific functions 100% host flash algo:
			--wr_prg_flash_byte(base_addr+byte_num, data, cur_bank, false)   --0.7KBps

			--EASIEST FIRMWARE SPEEDUP: 5x faster, create mapper write byte function:
			--dict.nes("MMC1_PRG_FLASH_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)
			--NEXT STEP: firmware write page/bank function can use function pointer for the function above
			--	this may cause issues with more complex algos
			--	sometimes cur bank is needed 
			--	for this to work, need to have function post conditions meet the preconditions
			--	that way host intervention is only needed for bank controls
			--	Is there a way to allow for double buffering though..?
			--	YES!  just think of the bank as a complete memory
			--	this greatly simplifies things and is exactly where we want to go
			--	This is completed below outside the byte while loop @ 39KBps

			--local verify = true
			if (verify) then
				readdata = dict.nes("NES_CPU_RD", base_addr+byte_num)
				if readdata ~= data then
					print("ERROR flashing byte number", byte_num, " in bank",cur_bank, " to flash ", data, readdata)
				end
			end

			byte_num = byte_num + 1
		end
		--]]

		--Have the device write a banks worth of data
		flash.write_file( file, bank_size/1024, mapname, "PRGROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")

end


--slow host flash one byte at a time...
--this is controlled from the host side byte by byte making it slow
--but doesn't require specific firmware mapper flashing functions
local function flash_chrrom(file, rom_size_KB, debug)

	init_mapper()

	print("\nProgramming CHR-ROM flash")

	--test some bytes
	--wr_chr_flash_byte(0x0000, 0xA5, 0, true)
	--wr_chr_flash_byte(0x0FFF, 0x5A, 0, true)
	

	local base_addr = 0x0000
	local bank_size = 4*1024 --MMC1 always write to PT0
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata


	while cur_bank < total_banks do

		if (cur_bank % 8 == 0) then
			print("writing CHR bank:", cur_bank, "of", total_banks - 1)
		end

		--select bank to flash
		dict.nes("SET_CUR_BANK", cur_bank) 
		if debug then print("get bank:", dict.nes("GET_CUR_BANK")) end
		--this only updates the firmware nes.c global
		--which it will use when calling mmc1_chrrom_flash_wr

		--program the entire bank's worth of data
		--[[  This version of the code programs a single byte at a time but doesn't require 
		--	mapper specific functions in the firmware
		print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware mapper specific functions 100% host flash algo:
			--wr_chr_flash_byte(base_addr+byte_num, data, cur_bank, false)  --0.7KBps
			--EASIEST FIRMWARE SPEEDUP: 5x faster, create mapper write byte function:
			dict.nes("MMC1_CHR_FLASH_WR", base_addr+byte_num, data) --3.8KBps (5.5x faster than above)
			--FASTEST have the firmware handle flashing a bank's worth of data
			--control the init and banking from the host side

			if (verify) then
				readdata = dict.nes("NES_PPU_RD", base_addr+byte_num)
				if readdata ~= data then
					print("ERROR flashing byte number", byte_num, " in bank",cur_bank, " to flash ", data, readdata)
				end
			end

			byte_num = byte_num + 1
		end
		--]]

		--Have the device write a "banks" worth of data, actually 2x banks of 2KB each
		--FAST!  13sec for 512KB = 39KBps
		flash.write_file( file, bank_size/1024, mapname, "CHRROM", false )

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
	-- MMC1 has RAM capability present in some carts
	local dumpram = process_opts["dumpram"]
	local ramdumpfile = process_opts["dumpram_filename"]
	local writeram = process_opts["writeram"]
	local ramwritefile = process_opts["writeram_filename"]

	local rv = nil
	local file
	local prg_size = console_opts["prg_rom_size_kb"]
	local chr_size = console_opts["chr_rom_size_kb"]
	local wram_size = console_opts["wram_size_kb"]

	local filetype = "bin"

	-- Initialize device I/O for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

	-- Test cart by reading manufacturer/product ID
	if test then
		print("Testing", mapname)

		-- Verify mirroring is behaving as expected
		mirror_test(true)

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

		-- Enable save RAM
		dict.nes("NES_MMC1_WR", 0xE000, 0x00)  -- bit4 RAM enable 0-enabled 1-disabled

		-- bit4 (CHR A16) is /CE pin for WRAM on SNROM
		dict.nes("NES_MMC1_WR", 0xA000, 0x02)  -- 4KB bank @ PT0  $2AAA cmd and writes
		dict.nes("NES_MMC1_WR", 0xC000, 0x05)  -- 4KB bank @ PT1  $5555 cmd fixed

		file = assert(io.open(ramdumpfile, "wb"))

		-- Dump cart into file
		dump_wram(file, wram_size, false)

		-- For save data safety disable WRAM, and deny writes
		dict.nes("NES_MMC1_WR", 0xE000, 0x10)  -- bit4 RAM enable 0-enabled 1-disabled

		-- bit4 (CHR A16) is /CE pin for WRAM on SNROM
		dict.nes("NES_MMC1_WR", 0xA000, 0x12)  -- 4KB bank @ PT0  $2AAA cmd and writes
		dict.nes("NES_MMC1_WR", 0xC000, 0x15)  -- 4KB bank @ PT1  $5555 cmd fixed

		-- Close file
		assert(file:close())

		print("DONE Dumping WRAM")
	end



--dump the cart to dumpfile
	if read then
		print("\nDumping PRG & CHR ROMs...")

		-- sizes
		local prg_size = console_opts["prg_rom_size_kb"]
		local chr_size = console_opts["chr_rom_size_kb"]

		-- Optional title-based override: BATTLE OF OLYMPUS uses CHR-RAM -> CHR must be 0
		local title = ((process_opts["cartname"] or process_opts["romname"] or dumpfile or "") .. ""):upper()
		if title:find("BATTLE OF OLYMPUS", 1, true) then
			chr_size = 0
		end

			-- Force Battle of Olympus to use Mouse Bite Labs MMC1 approach
		if title:find("BATTLE OF OLYMPUS", 1, true) then
			print("DEBUG: Battle of Olympus detected - using Mouse Bite Labs MMC1 approach")
			
			-- Based on Mouse Bite Labs reproduction board guide - try different hardware configurations
			print("DEBUG: Trying different MMC1 hardware configurations from Mouse Bite Labs guide")
			
			-- Try SLROM configuration (CHR ROM, no WRAM)
			print("DEBUG: Attempting SLROM configuration (CHR ROM, no WRAM)")
			dict.nes("NES_CPU_WR", 0x8000, 0x80) -- Reset shift register
			
			-- SLROM control register: 0x0C = 00001100b
			-- M=00 (1-screen mirroring), H=0 (8000-BFFF fixed), F=1 (16K), C=0 (8K CHR)
			local control_value = 0x0C
			dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
			control_value = control_value >> 1
			dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
			control_value = control_value >> 1
			dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
			control_value = control_value >> 1
			dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
			control_value = control_value >> 1
			dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
			
			-- Set CHR bank 0
			local chr_value = 0x00
			dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
			chr_value = chr_value >> 1
			dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
			chr_value = chr_value >> 1
			dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
			chr_value = chr_value >> 1
			dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
			chr_value = chr_value >> 1
			dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
			
			-- Set PRG bank 0 (no WRAM)
			local prg_value = 0x00
			dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
			prg_value = prg_value >> 1
			dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
			prg_value = prg_value >> 1
			dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
			prg_value = prg_value >> 1
			dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
			prg_value = prg_value >> 1
			dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
			
			-- Test SLROM configuration
			print("DEBUG: Testing SLROM configuration:")
			local test_bytes = {}
			for j = 0, 15 do
				test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
			end
			local byte_str = ""
			for j = 1, 16 do
				byte_str = byte_str .. string.format("%02X ", test_bytes[j])
			end
			print("  " .. byte_str)
			
			local has_variation = false
			for j = 1, 16 do
				if test_bytes[j] ~= 0xFF then
					has_variation = true
					break
				end
			end
			
			if has_variation then
				print("DEBUG: SLROM configuration worked - using Mouse Bite Labs approach")
				file = assert(io.open(dumpfile, "wb"))
				create_header(file, prg_size, chr_size)
				dump_prgrom_mouse_bite_labs_style(file, prg_size, true)
			else
				-- Try SNROM configuration (CHR RAM, WRAM)
				print("DEBUG: SLROM failed, trying SNROM configuration (CHR RAM, WRAM)")
				dict.nes("NES_CPU_WR", 0x8000, 0x80) -- Reset shift register
				
				-- SNROM control register: 0x0C = 00001100b (same as SLROM)
				control_value = 0x0C
				dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
				control_value = control_value >> 1
				dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
				control_value = control_value >> 1
				dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
				control_value = control_value >> 1
				dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
				control_value = control_value >> 1
				dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
				
				-- Set CHR bank 0
				chr_value = 0x00
				dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
				chr_value = chr_value >> 1
				dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
				chr_value = chr_value >> 1
				dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
				chr_value = chr_value >> 1
				dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
				chr_value = chr_value >> 1
				dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
				
				-- Set PRG bank 0 with WRAM enabled (0x10)
				prg_value = 0x10
				dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
				prg_value = prg_value >> 1
				dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
				prg_value = prg_value >> 1
				dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
				prg_value = prg_value >> 1
				dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
				prg_value = prg_value >> 1
				dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
				
				-- Test SNROM configuration
				print("DEBUG: Testing SNROM configuration:")
				for j = 0, 15 do
					test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
				end
				byte_str = ""
				for j = 1, 16 do
					byte_str = byte_str .. string.format("%02X ", test_bytes[j])
				end
				print("  " .. byte_str)
				
				has_variation = false
				for j = 1, 16 do
					if test_bytes[j] ~= 0xFF then
						has_variation = true
						break
					end
				end
				
				if has_variation then
					print("DEBUG: SNROM configuration worked - using Mouse Bite Labs approach")
					file = assert(io.open(dumpfile, "wb"))
					create_header(file, prg_size, chr_size)
					dump_prgrom_mouse_bite_labs_style(file, prg_size, true)
				else
					print("DEBUG: All Mouse Bite Labs configurations failed - trying standard init sequence")
					-- Try using the exact same initialization as the standard mapper
					print("DEBUG: Using standard MMC1 initialization sequence")
					dict.nes("NES_CPU_RD", 0x8000)
					dict.nes("NES_CPU_WR", 0x8000, 0x80) -- Reset shift register
					
					-- Use exact same control register as standard init: 0x10
					-- Control register: 0x10 = 00010000b
					-- M=00 (1-screen mirroring), H=1 (8000-BFFF switchable), F=0 (32K), C=0 (8K CHR)
					print("DEBUG: Setting control register to 0x10 (standard)")
					local control_value = 0x10
					dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
					control_value = control_value >> 1
					dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
					control_value = control_value >> 1
					dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
					control_value = control_value >> 1
					dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
					control_value = control_value >> 1
					dict.nes("NES_MMC1_WR", 0x8000, control_value & 0x01)
					
					-- Use exact same PRG bank as standard init: 0x10 (WRAM disabled)
					print("DEBUG: Setting PRG bank to 0x10 (standard)")
					local prg_value = 0x10
					dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
					prg_value = prg_value >> 1
					dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
					prg_value = prg_value >> 1
					dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
					prg_value = prg_value >> 1
					dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
					prg_value = prg_value >> 1
					dict.nes("NES_MMC1_WR", 0xE000, prg_value & 0x01)
					
					-- Use exact same CHR banks as standard init: 0x12 and 0x15
					print("DEBUG: Setting CHR banks to 0x12 and 0x15 (standard)")
					local chr_value = 0x12
					dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
					chr_value = chr_value >> 1
					dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
					chr_value = chr_value >> 1
					dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
					chr_value = chr_value >> 1
					dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
					chr_value = chr_value >> 1
					dict.nes("NES_MMC1_WR", 0xA000, chr_value & 0x01)
					
					chr_value = 0x15
					dict.nes("NES_MMC1_WR", 0xC000, chr_value & 0x01)
					chr_value = chr_value >> 1
					dict.nes("NES_MMC1_WR", 0xC000, chr_value & 0x01)
					chr_value = chr_value >> 1
					dict.nes("NES_MMC1_WR", 0xC000, chr_value & 0x01)
					chr_value = chr_value >> 1
					dict.nes("NES_MMC1_WR", 0xC000, chr_value & 0x01)
					chr_value = chr_value >> 1
					dict.nes("NES_MMC1_WR", 0xC000, chr_value & 0x01)
					
					-- Test if standard initialization worked
					print("DEBUG: Testing standard initialization:")
					local test_bytes = {}
					for j = 0, 15 do
						test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
					end
					local byte_str = ""
					for j = 1, 16 do
						byte_str = byte_str .. string.format("%02X ", test_bytes[j])
					end
					print("  " .. byte_str)
					
					local has_variation = false
					for j = 1, 16 do
						if test_bytes[j] ~= 0xFF then
							has_variation = true
							break
						end
					end
					
					if has_variation then
						print("DEBUG: Standard initialization worked - using standard approach")
						file = assert(io.open(dumpfile, "wb"))
						create_header(file, prg_size, chr_size)
						dump_prgrom_standard_style(file, prg_size, true)
					else
						print("DEBUG: Standard initialization failed - trying power-on default state")
						-- Try to read PRG-ROM without ANY initialization
						-- Maybe Battle of Olympus works in its power-on default state
						print("DEBUG: Attempting to read PRG-ROM in power-on default state")
						local test_bytes = {}
						for j = 0, 15 do
							test_bytes[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
						end
						local byte_str = ""
						for j = 1, 16 do
							byte_str = byte_str .. string.format("%02X ", test_bytes[j])
						end
						print("DEBUG: Power-on default state test reads $8000-$800F:")
						print("  " .. byte_str)
						
						local has_variation = false
						for j = 1, 16 do
							if test_bytes[j] ~= 0xFF then
								has_variation = true
								break
							end
						end
						
						if has_variation then
							print("DEBUG: Power-on default state worked - using power-on approach")
							file = assert(io.open(dumpfile, "wb"))
							create_header(file, prg_size, chr_size)
							dump_prgrom_poweron_default(file, prg_size, true)
						else
							print("DEBUG: Power-on default state also failed - trying real NES power-on sequence")
							-- Since the cart works on real NES, try to mimic real NES power-on sequence
							print("DEBUG: Attempting to mimic real NES power-on sequence")
							
							-- Real NES power-on sequence:
							-- 1. Power on
							-- 2. Reset pulse
							-- 3. CPU starts executing from $FFFC (reset vector)
							-- 4. Game initializes MMC1
							
							-- Try to trigger a reset sequence
							print("DEBUG: Triggering reset sequence")
							dict.nes("NES_CPU_RD", 0x8000)  -- Read to stabilize
							dict.nes("NES_CPU_WR", 0x8000, 0x80)  -- Reset MMC1
							
							-- Wait a bit (simulate real NES timing)
							for i = 1, 100 do
								dict.nes("NES_CPU_RD", 0x8000)
							end
							
							-- Try to read reset vector area
							print("DEBUG: Reading reset vector area $FFFC-$FFFF")
							local reset_vector = {}
							for j = 0, 3 do
								reset_vector[j+1] = dict.nes("NES_CPU_RD", 0xFFFC + j)
							end
							print("DEBUG: Reset vector:", string.format("%02X %02X %02X %02X", reset_vector[1], reset_vector[2], reset_vector[3], reset_vector[4]))
							
							-- Try reading from the reset vector address
							local reset_addr = reset_vector[1] + (reset_vector[2] * 256)
							print("DEBUG: Reset address:", string.format("0x%04X", reset_addr))
							
							-- Try reading from reset address and surrounding area
							print("DEBUG: Reading from reset address area")
							local test_bytes = {}
							for j = 0, 15 do
								test_bytes[j+1] = dict.nes("NES_CPU_RD", reset_addr + j)
							end
							local byte_str = ""
							for j = 1, 16 do
								byte_str = byte_str .. string.format("%02X ", test_bytes[j])
							end
							print("DEBUG: Reset address area reads:")
							print("  " .. byte_str)
							
							-- Also try reading from $8000 after reset
							print("DEBUG: Reading from $8000 after reset")
							local test_bytes2 = {}
							for j = 0, 15 do
								test_bytes2[j+1] = dict.nes("NES_CPU_RD", 0x8000 + j)
							end
							local byte_str2 = ""
							for j = 1, 16 do
								byte_str2 = byte_str2 .. string.format("%02X ", test_bytes2[j])
							end
							print("DEBUG: $8000 area reads after reset:")
							print("  " .. byte_str2)
							
							local has_variation = false
							for j = 1, 16 do
								if test_bytes[j] ~= 0xFF or test_bytes2[j] ~= 0xFF then
									has_variation = true
									break
								end
							end
							
							if has_variation then
								print("DEBUG: Real NES power-on sequence worked - using real NES approach")
								file = assert(io.open(dumpfile, "wb"))
								create_header(file, prg_size, chr_size)
								dump_prgrom_real_nes_sequence(file, prg_size, true)
							else
								print("DEBUG: Real NES power-on sequence also failed - trying manual byte-by-byte dump")
								file = assert(io.open(dumpfile, "wb"))
								create_header(file, prg_size, chr_size)
								dump_prgrom_manual(file, prg_size, true)
							end
						end
					end
				end
			end
		else
		-- Use standard approach for all other games
		print("DEBUG: Using standard approach with fallback")
		init_mapper()
		
		file = assert(io.open(dumpfile, "wb"))
		
		-- header first
		create_header(file, prg_size, chr_size)
		
		-- PRG: use original, fallback to mode 2 if nothing was written
		dump_prgrom_with_fallback(file, prg_size, true) -- Enable debug for better feedback
		end

		-- CHR only if present
		if chr_size > 0 then
			if chr_size > 0 then dump_chrrom(file, chr_size, false) end
		end

		assert(file:close())

		print("DONE Dumping PRG & CHR ROMs")
	end


	-- Erase the cart
	if erase then
		print("\nErasing", mapname)

		print("erasing PRG-ROM")
		dict.nes("NES_CPU_WR", 0xD555, 0xAA)
		dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xD555, 0x80)
		dict.nes("NES_CPU_WR", 0xD555, 0xAA)
		dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xD555, 0x10)
		rv = dict.nes("NES_CPU_RD", 0x8000)

		local i = 0

		--TODO create some function to pass the read value 
		--that's smart enough to figure out if the board is actually erasing or not
		while ( rv ~= 0xFF ) do
			rv = dict.nes("NES_CPU_RD", 0x8000)
			i = i + 1
		end
		print(i, "naks, done erasing prg.")

		-- TODO: erase CHR-ROM only if present
		if (chr_size ~= 0) then
			init_mapper()

			print("erasing CHR-ROM")
			dict.nes("NES_PPU_WR", 0x1555, 0xAA)
			dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
			dict.nes("NES_PPU_WR", 0x1555, 0x80)
			dict.nes("NES_PPU_WR", 0x1555, 0xAA)
			dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
			dict.nes("NES_PPU_WR", 0x1555, 0x10)
			rv = dict.nes("NES_PPU_RD", 0x8000)

			local i = 0

			--TODO create some function to pass the read value 
			--that's smart enough to figure out if the board is actually erasing or not
			while ( rv ~= 0xFF ) do
				rv = dict.nes("NES_PPU_RD", 0x8000)
				i = i + 1
			end
			print(i, "naks, done erasing chr.");
		end


	end

	-- Write to WRAM on the cart
	if writeram then
		print("\nWriting to WRAM...")

		init_mapper()

		-- Enable save RAM
		dict.nes("NES_MMC1_WR", 0xE000, 0x00)  -- bit4 RAM enable 0-enabled 1-disabled

		-- bit4 (CHR A16) is /CE pin for WRAM on SNROM
		dict.nes("NES_MMC1_WR", 0xA000, 0x02)  -- 4KB bank @ PT0  $2AAA cmd and writes
		dict.nes("NES_MMC1_WR", 0xC000, 0x05)  -- 4KB bank @ PT1  $5555 cmd fixed

		file = assert(io.open(ramwritefile, "rb"))

		flash.write_file(file, wram_size, "NOVAR", "PRGRAM", false)

		-- For save data safety disable WRAM, and deny writes
		dict.nes("NES_MMC1_WR", 0xE000, 0x10)  -- bit4 RAM enable 0-enabled 1-disabled

		-- bit4 (CHR A16) is /CE pin for WRAM on SNROM
		dict.nes("NES_MMC1_WR", 0xA000, 0x12)  -- 4KB bank @ PT0  $2AAA cmd and writes
		dict.nes("NES_MMC1_WR", 0xC000, 0x15)  -- 4KB bank @ PT1  $5555 cmd fixed

		-- Close file
		assert(file:close())

		print("DONE Writing WRAM")
	end


	-- Program flashfile to the cart
	if program then
		-- Open file
		file = assert(io.open(flashfile, "rb"))
		-- Determine if auto-doubling, deinterleaving, etc.
		-- needs done to make board compatible with ROM


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

		-- Flash cart
		flash_prgrom(file, prg_size, false)
		flash_chrrom(file, chr_size, false)

		-- Close file
		assert(file:close())
	end

	-- Verify flashfile is on the cart
	if verify then
		-- For now let's just dump the file and verify manually
		print("\nPost dumping PRG & CHR ROMs...")

		init_mapper()

		file = assert(io.open(verifyfile, "wb"))

		-- Dump cart into file
		dump_prgrom(file, prg_size, false)
		if chr_size > 0 then dump_chrrom(file, chr_size, false) end

		-- Close file
		assert(file:close())

		print("DONE post dumping PRG & CHR ROMs")
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
mmc1.process = process

-- return the module's table
return mmc1