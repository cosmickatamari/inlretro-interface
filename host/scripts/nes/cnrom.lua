-- CNROM mapper for INL Retro
-- Supports iNES mapper 3 (CNROM)

local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"

local cnrom = {}

-- File constants
local mapname = "CNROM"
local banktable_base = 0x8000

-- local functions
local function find_ff_write_addr()
  -- scan for a PRG location that reads $FF to avoid bus conflicts
  for a = 0x8000, 0xFFFF do
    local v = dict.nes("NES_CPU_RD", a)
    if v == 0xFF then return a end
  end
  -- fallback (won't be ideal, but prevents nil)
  return 0x8000
end

local function create_header(file, prgKB, chrKB)
	local mirroring = nes.detect_mapper_mirroring()
	nes.write_header(file, prgKB, chrKB, op_buffer[mapname], mirroring)
end

-- Read PRG-ROM flash ID (identical to NROM)
local function prgrom_manf_id(debug)
	if debug then print("reading PRG-ROM manf ID") end

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


-- Read CHR-ROM flash ID
local function chrrom_manf_id(debug)
	if debug then print("reading CHR-ROM manf ID") end

	-- Enter software ID mode
	-- CNROM has A13 & A14 register controlled lower 2 bits of mapper
	-- Address mapping: 0x5 = $1555, 0x2 = $0AAA
	dict.nes("NES_CPU_WR", banktable_base + 2, 0x02)
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)

	dict.nes("NES_CPU_WR", banktable_base + 1, 0x01)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)

	dict.nes("NES_CPU_WR", banktable_base + 2, 0x02)
	dict.nes("NES_PPU_WR", 0x1555, 0x90)

	-- Read manufacturer ID
	local rv = dict.nes("NES_PPU_RD", 0x0000)
	if debug then print("attempted read CHR-ROM manf ID:", string.format("%X", rv)) end

	-- Read product ID
	rv = dict.nes("NES_PPU_RD", 0x0001)
	if debug then print("attempted read CHR-ROM prod ID:", string.format("%X", rv)) end

	-- Exit software ID mode
	dict.nes("NES_PPU_WR", 0x0000, 0xF0)
end


-- Dump the PRG ROM (same as NROM)
local function dump_prgrom(file, rom_size_KB, debug)
	local KB_per_read = 32
	if rom_size_KB < KB_per_read then KB_per_read = rom_size_KB end

	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x08  -- $8000

	while (read_count < num_reads) do
		if debug then print("dump PRG part", read_count, "of", num_reads) end

		dump.dumptofile(file, KB_per_read, addr_base, "NESCPU_4KB", false)

		read_count = read_count + 1
	end
end

-- Dump the CHR ROM
local function dump_chrrom(file, rom_size_KB, debug)
	local KB_per_read = 8
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00  -- $0000

	-- Pick a safe address to write bank value (ROM byte must be $FF)
	local ff_addr = find_ff_write_addr()
	if debug then print(string.format("CNROM bank select write addr: $%04X", ff_addr)) end

	-- Determine how many bank bits we should respect
	-- 8 KB per CHR bank
	local total_banks = num_reads
	-- CNROM variants commonly have 2 or 4 bank bits
	local bank_mask = (total_banks <= 4) and 0x03 or 0x0F

	while (read_count < num_reads) do
		if debug then print("dump CHR part", read_count, "of", num_reads) end

		local bank = bit32.band(read_count, bank_mask)

		-- Single write: avoid changing addresses; avoid bus conflicts with non-$FF bytes
		dict.nes("NES_CPU_WR", ff_addr, bank)

		-- Dump this bank (8 KB)
		dump.dumptofile(file, KB_per_read, addr_base, "NESPPU_1KB", false)

		read_count = read_count + 1
	end
end



-- Write a single byte to PRG-ROM flash
local function wr_prg_flash_byte(addr, value, debug)
	if (addr < 0x8000 or addr > 0xFFFF) then
		print("\n  ERROR! flash write to PRG-ROM", string.format("$%X", addr), "must be $8000-FFFF \n\n")
		return
	end

	-- Send unlock command and write byte
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xA0)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", addr, value)

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
-- REQ: addr must be within Pattern Tables ($0000-1FFF)
local function wr_chr_flash_byte(bank, addr, value, debug)
	if (addr < 0x0000 or addr > 0x1FFF) then
		print("\n  ERROR! flash write to CHR-ROM", string.format("$%X", addr), "must be $0000-1FFF \n\n")
		return
	end

	-- Send unlock command
	dict.nes("NES_CPU_WR", banktable_base + 2, 0x02)
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)

	dict.nes("NES_CPU_WR", banktable_base + 1, 0x01)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)

	dict.nes("NES_CPU_WR", banktable_base + 2, 0x02)
	dict.nes("NES_PPU_WR", 0x1555, 0xA0)

	-- Select desired bank and write the byte
	dict.nes("NES_CPU_WR", banktable_base + bank, bank)
	dict.nes("NES_PPU_WR", addr, value)

	local rv = dict.nes("NES_PPU_RD", addr)
	local i = 0

	while (rv ~= value) do
		rv = dict.nes("NES_PPU_RD", addr)
		i = i + 1
	end
	if debug then print(i, "naks, done writing byte.") end
end



local function flash_prgrom(file, rom_size_KB, debug)
	print("\nProgramming PRG-ROM flash")

	local bank_size = 32 * 1024  -- 32KB per PRG bank
	local cur_bank = 0
	local total_banks = rom_size_KB * 1024 / bank_size

	while cur_bank < total_banks do
		if (cur_bank % 8 == 0) then
			print("writing PRG bank:", cur_bank, "of", total_banks - 1)
		end

		-- Program the entire bank's worth of data (same as NROM)
		flash.write_file(file, 32, "NROM", "PRGROM", false)

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")
end


local function flash_chrrom(file, rom_size_KB, debug)
	print("\nProgramming CHR-ROM flash")

	local bank_size = 8 * 1024  -- 8KB per CHR bank
	local cur_bank = 0
	local total_banks = rom_size_KB * 1024 / bank_size

	-- Set the bank table address
	dict.nes("SET_BANK_TABLE", banktable_base)
	if debug then print("get banktable:", string.format("%X", dict.nes("GET_BANK_TABLE"))) end

	while cur_bank < total_banks do
		if (cur_bank % 8 == 0) then
			print("writing CHR bank:", cur_bank, "of", total_banks - 1)
		end

		-- Select bank to flash
		dict.nes("SET_CUR_BANK", cur_bank)
		if debug then print("get bank:", dict.nes("GET_CUR_BANK")) end
		-- This only updates the firmware nes.c global
		-- which it will use when calling cnrom_chrrom_flash_wr

		-- Program the entire bank's worth of data
		flash.write_file(file, 8, mapname, "CHRROM", false)

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

	local filetype = "nes"

	-- Initialize device I/O for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

	-- Test the cart
	if test then
		print("Testing", mapname)
		nes.detect_mapper_mirroring(true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))
		prgrom_manf_id(true)
		chrrom_manf_id(true)
	end

	-- Dump the cart to dumpfile
	if read then
		print("\nDumping PRG & CHR ROMs...")

		file = assert(io.open(dumpfile, "wb"))

		-- Create header: pass open & empty file & ROM sizes
		create_header(file, prg_size, chr_size)

		-- Dump cart into file
		dump_prgrom(file, prg_size, true)
		dump_chrrom(file, chr_size, true)

		-- Close file
		assert(file:close())
		print("DONE Dumping PRG & CHR ROMs")
	end

	-- Erase the cart
	if erase then
		print("\nErasing", mapname)

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

		print("erasing CHR-ROM")
		-- If PRG-ROM is erased (all 0xFF), MCU should be able to write to any address
		dict.nes("NES_CPU_WR", banktable_base + 2, 0x02)
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_CPU_WR", banktable_base + 1, 0x01)
		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
		dict.nes("NES_CPU_WR", banktable_base + 2, 0x02)
		dict.nes("NES_PPU_WR", 0x1555, 0x80)
		dict.nes("NES_CPU_WR", banktable_base + 2, 0x02)
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_CPU_WR", banktable_base + 1, 0x01)
		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
		dict.nes("NES_CPU_WR", banktable_base + 2, 0x02)
		dict.nes("NES_PPU_WR", 0x1555, 0x10)

		rv = dict.nes("NES_PPU_RD", 0x0000)

		i = 0
		while (rv ~= 0xFF) do
			rv = dict.nes("NES_PPU_RD", 0x0000)
			i = i + 1
		end
		print(i, "naks, done erasing chr.\n")
	end

	-- Program flashfile to the cart
	if program then
		file = assert(io.open(flashfile, "rb"))

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
		print("\nPost Dumping PRG & CHR ROMs...")

		file = assert(io.open(verifyfile, "wb"))

		-- Dump cart into file
		dump_prgrom(file, prg_size, false)
		dump_chrrom(file, chr_size, false)

		-- Close file
		assert(file:close())
		print("DONE Post Dumping PRG & CHR ROMs")
	end

	dict.io("IO_RESET")
end

-- Functions other modules are able to call
cnrom.process = process

-- Return the module's table
return cnrom
