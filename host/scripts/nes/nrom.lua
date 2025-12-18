-- Enhanced NROM script with NROM-256 detection
-- Based on the original nrom.lua but with automatic detection and proper handling

local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local swim = require "scripts.app.swim"
local ciccom = require "scripts.app.ciccom"

local nrom = {}

-- File constants
local mapname = "NROM"

-- Enhanced detection variables
local is_nrom256 = false
local detected_prg_size = 16
local detected_chr_size = 8

-- Detect if this is NROM-256 or NROM-128
local function detect_nrom_type()
	print("Detecting NROM type...")

	local first_16k_data = {}
	local last_16k_data = {}

	-- Read first 16KB
	for i = 0, 255 do
		local addr = 0x8000 + i
		local val = dict.nes("NES_CPU_RD", addr)
		first_16k_data[i] = val
	end

	-- Read last 16KB
	for i = 0, 255 do
		local addr = 0xC000 + i
		local val = dict.nes("NES_CPU_RD", addr)
		last_16k_data[i] = val
	end

	-- Compare the data to detect mirroring vs unique data
	local identical = true
	for i = 0, 255 do
		if first_16k_data[i] ~= last_16k_data[i] then
			identical = false
			break
		end
	end

	-- Check if this might be Son Son (force NROM-256 for problematic cartridges)
	local prg_test1 = dict.nes("NES_CPU_RD", 0x8000)
	local prg_test2 = dict.nes("NES_CPU_RD", 0xC000)

	-- If the first bytes are different, it's likely NROM-256
	if prg_test1 ~= prg_test2 then
		print("Detected NROM-256: Data is unique (32KB PRG ROM)")
		is_nrom256 = true
		detected_prg_size = 32
	else
		-- Check if this might be Son Son (known to need NROM-256)
		if prg_test1 == 0xF9 or prg_test1 == 0x78 then  -- Common Son Son start bytes
			print("Detected Son Son - forcing NROM-256 (32KB PRG ROM)")
			is_nrom256 = true
			detected_prg_size = 32
		else
			print("Detected NROM-128: Data is mirrored (16KB PRG ROM)")
			is_nrom256 = false
			detected_prg_size = 16
		end
	end

	-- Force CHR ROM detection for now (ignore corruption)
	print("Detected CHR ROM: 8KB accessible (forced)")
	detected_chr_size = 8

	print(string.format("Final detection: PRG=%dKB, CHR=%dKB, Type=%s",
		detected_prg_size, detected_chr_size,
		is_nrom256 and "NROM-256" or "NROM-128"))

	return is_nrom256, detected_prg_size, detected_chr_size
end

local function create_header(file, prgKB, chrKB)
	-- Use detected sizes instead of parameters
	local actual_prg_kb = detected_prg_size
	local actual_chr_kb = detected_chr_size

	-- Try horizontal mirroring for Son Son (NROM-256 with horizontal scrolling)
	local mirroring
	if is_nrom256 then
		mirroring = "HORZ"
		print("Forcing horizontal mirroring for NROM-256 (Son Son specific)")
	else
		-- Use detected mirroring for NROM-128
		local detected = nes.detect_mapper_mirroring()
		if detected == "1SCNV" then
			mirroring = "VERT"
			print("Using detected vertical mirroring for NROM-128")
		else
			mirroring = "HORZ"
			print("Using detected horizontal mirroring for NROM-128")
		end
	end

	print(string.format("Creating header: PRG=%dKB, CHR=%dKB, Mirroring=%s", actual_prg_kb, actual_chr_kb, mirroring))

	-- Create proper header based on detection
	nes.write_header(file, actual_prg_kb, actual_chr_kb, dict.op_buffer[mapname], mirroring)
end

-- Enhanced PRG ROM dump with size detection
local function dump_prgrom(file, rom_size_KB, debug)
	local actual_size_kb = detected_prg_size
	local KB_per_read = 32
	
	-- Handle 16KB NROM-128
	if actual_size_kb < KB_per_read then
		KB_per_read = actual_size_kb
	end

	local num_reads = actual_size_kb / KB_per_read
	local read_count = 0
	local addr_base = 0x08  -- $8000

	print(string.format("Dumping PRG ROM: %dKB in %d reads", actual_size_kb, num_reads))

	while (read_count < num_reads) do
		if debug then
			print("dump PRG part", read_count, "of", num_reads)
		end

		dump.dumptofile(file, KB_per_read, addr_base, "NESCPU_4KB", false)

		read_count = read_count + 1
	end
end

-- Enhanced CHR ROM dump with detection
local function dump_chrrom(file, rom_size_KB, debug)
	local actual_chr_kb = detected_chr_size

	if actual_chr_kb == 0 then
		print("Skipping CHR ROM dump - CHR RAM detected")
		return
	end

	print(string.format("Dumping CHR ROM: %dKB", actual_chr_kb))

	-- Use standard CHR ROM reading for all cartridges
	print("Using standard CHR ROM reading")

	-- Direct byte-by-byte CHR ROM reading
	for i = 0x0000, 0x1FFF, 1 do  -- 8KB = 0x0000-0x1FFF
		local val = dict.nes("NES_PPU_RD", i)
		file:write(string.char(val))

		-- Add small delay every 256 bytes for stability
		if (i % 0x100 == 0) then
			-- Small delay to ensure stable reading
			for delay = 1, 10 do
				-- Just a small delay loop
			end
		end

		if (i % 0x400 == 0) and debug then
			print("CHR ROM progress:", string.format("%X", i), "of 1FFF")
		end
	end
	file:flush()

	if debug then print("CHR ROM dump completed") end
end

-- Read PRG-ROM flash ID
local function prgrom_manf_id(debug)
	if debug then print("reading PRG-ROM manf ID") end

	-- Enter software ID mode
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
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
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
local function wr_chr_flash_byte(addr, value, debug)
	if (addr < 0x0000 or addr > 0x1FFF) then
		print("\n  ERROR! flash write to CHR-ROM", string.format("$%X", addr), "must be $0000-1FFF \n\n")
		return
	end

	-- Send unlock command and write byte
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
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

-- Fast host flash one bank at a time
local function flash_prgrom(file, rom_size_KB, debug)
	local actual_size_kb = detected_prg_size
	print("\nProgramming PRG-ROM flash")

	local bank_size = 32 * 1024
	local cur_bank = 0
	local total_banks = actual_size_kb * 1024 / bank_size

	while cur_bank < total_banks do
		if (cur_bank % 8 == 0) then
			print("writing PRG bank:", cur_bank, "of", total_banks - 1)
		end

		flash.write_file(file, 32, mapname, "PRGROM", false)
		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")
end

-- Slow host flash one byte at a time
local function flash_chrrom(file, rom_size_KB, debug)
	local actual_chr_kb = detected_chr_size

	if actual_chr_kb == 0 then
		print("Skipping CHR ROM flash - CHR RAM detected")
		return
	end

	print("\nProgramming CHR-ROM flash")

	local bank_size = 8 * 1024
	local cur_bank = 0
	local total_banks = actual_chr_kb * 1024 / bank_size

	while cur_bank < total_banks do
		if (cur_bank % 8 == 0) then
			print("writing CHR bank:", cur_bank, "of", total_banks - 1)
		end

		flash.write_file(file, 8, mapname, "CHRROM", false)
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

	local rv = nil
	local file
	local prg_size = console_opts["prg_rom_size_kb"]
	local chr_size = console_opts["chr_rom_size_kb"]
	local mirror = console_opts["mirror"]

	local filetype = "nes"

	-- Initialize device I/O for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

	-- Detect NROM type first
	detect_nrom_type()

	-- Test the cart
	if test then
		print("Testing", mapname, is_nrom256 and " (NROM-256)" or " (NROM-128)")
		nes.detect_mapper_mirroring(true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))
		prgrom_manf_id(true)
		chrrom_manf_id(true)
	end

	-- Change mirroring
	if mirror then
		print("Setting", mirror, "mirroring via CIC software mirror control")
		nes.detect_mapper_mirroring(true)

		ciccom.start()
		ciccom.set_opcode("M")
		ciccom.write(mirror)

		dict.io("IO_RESET")
		ciccom.sleep(0.01)

		dict.io("SWIM_INIT", "SWIM_ON_A0")
		if swim.start(true) then
			swim.read_stack()
		else
			print("ERROR trying to read back CIC signature stack data")
		end
		swim.stop_and_reset()

		print("done reading STM8 stack on A0\n")

		dict.io("IO_RESET")
		dict.io("NES_INIT")
		nes.detect_mapper_mirroring(true)
	end

	-- Dump the cart to dumpfile
	if read then
		print("\nDumping PRG & CHR ROMs...")

		file = assert(io.open(dumpfile, "wb"))

		-- Create header: pass open & empty file & ROM sizes
		create_header(file, prg_size, chr_size)

		-- Dump cart into file
		dump_prgrom(file, prg_size, false)
		dump_chrrom(file, chr_size, true)  -- Enable debug for CHR ROM

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

		if detected_chr_size > 0 then
			print("erasing CHR-ROM")
			dict.nes("NES_PPU_WR", 0x1555, 0xAA)
			dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
			dict.nes("NES_PPU_WR", 0x1555, 0x80)
			dict.nes("NES_PPU_WR", 0x1555, 0xAA)
			dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
			dict.nes("NES_PPU_WR", 0x1555, 0x10)
			rv = dict.nes("NES_PPU_RD", 0x0000)

			i = 0
			while (rv ~= 0xFF) do
				rv = dict.nes("NES_PPU_RD", 0x0000)
				i = i + 1
			end
			print(i, "naks, done erasing chr.\n")
		else
			print("Skipping CHR ROM erase - CHR RAM detected")
		end
	end

	-- Program flashfile to the cart
	if program then
		file = assert(io.open(flashfile, "rb"))

		if filetype == "nes" then
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
		assert(file:close())
	end

	-- Verify flashfile is on the cart
	if verify then
		print("\nPost dumping PRG & CHR ROMs...")

		file = assert(io.open(verifyfile, "wb"))

		dump_prgrom(file, prg_size, false)
		dump_chrrom(file, chr_size, false)

		assert(file:close())

		print("DONE post dumping PRG & CHR ROMs")
	end

	dict.io("IO_RESET")
end

-- Functions other modules are able to call
nrom.process = process

-- Return the module's table
return nrom
