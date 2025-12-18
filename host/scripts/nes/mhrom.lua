-- GxROM/MHROM mapper for INL Retro
-- Supports iNES mapper 66 (GxROM/MHROM)
-- Super Mario Bros./Duck Hunt multicart uses this mapper

local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local time = require "scripts.app.time"
local dump = require "scripts.app.dump"

local gxrom = {}

-- Create iNES header with mapper 66, mirroring auto-detected if available
local function create_header(file, prgKB, chrKB)
	local mirroring = "V"
	if nes.detect_mapper_mirroring then
		mirroring = nes.detect_mapper_mirroring() or "V"
	end
	local mapper_id = 66
	nes.write_header(file, prgKB, chrKB, mapper_id, mirroring)
end

-- Dump PRG ROM using GxROM bank switching
local function dump_prgrom(file, rom_size_KB, debug)
	local KB_per_read = 32
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x08  -- $8000

	while (read_count < num_reads) do
		if debug then print("dump PRG part", read_count, "of", num_reads) end

		-- Select desired bank to dump
		-- Mapper 66 bank register is $8000-$FFFF
		-- Bits 4 and 5 specify PRG-ROM bank
		dict.nes("NES_CPU_WR", 0x8000, read_count << 4)  -- 32KB @ CPU $8000

		dump.dumptofile(file, KB_per_read, addr_base, "NESCPU_4KB", false)

		read_count = read_count + 1
	end
end

-- Dump CHR ROM using GxROM bank switching
local function dump_chrrom(file, rom_size_KB, debug)
	local KB_per_read = 8
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00  -- $0000-$1FFF

	while (read_count < num_reads) do
		if debug then print("dump CHR part", read_count, "of", num_reads) end

		-- Select desired bank to dump
		-- Mapper 66 bank register is $8000-$FFFF
		-- Bits 0 and 1 specify CHR-ROM bank
		dict.nes("NES_CPU_WR", 0x8000, read_count)  -- 8KB @ PPU $0000

		dump.dumptofile(file, KB_per_read, addr_base, "NESPPU_1KB", false)

		read_count = read_count + 1
	end
end

function gxrom.process(process_opts, console_opts)
	local test = process_opts["test"]
	local read = process_opts["read"]
	local verify = process_opts["verify"]
	local dumpfile = process_opts["dump_filename"]

	local file
	local prg_size = console_opts["prg_rom_size_kb"]
	local chr_size = console_opts["chr_rom_size_kb"]

	-- Initialize device I/O for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

	-- Test cart by reading manufacturer/product ID
	if test then
		print("Testing GxROM (mapper 66)")
		nes.detect_mapper_mirroring(true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))
	end

	-- Dump the cart to dumpfile
	if read then
		print("\nDumping PRG & CHR ROMs...")
		file = assert(io.open(dumpfile, "wb"))

		-- Create header: pass open & empty file & ROM sizes
		create_header(file, prg_size, chr_size)

		-- Dump cart into file
		time.start()
		dump_prgrom(file, prg_size, false)
		time.report(prg_size)

		time.start()
		dump_chrrom(file, chr_size, false)
		time.report(chr_size)

		-- Close file
		assert(file:close())
		print("DONE Dumping PRG & CHR ROMs")
	end

	dict.io("IO_RESET")
end

return gxrom
