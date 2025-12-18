--[[
	SNES ROM Dumper/Programmer - HiROM Support Module
	Supports both LoROM and HiROM mapping modes
	Handles special cases for EarthBound, SimEarth, SuperFX (GSU-1), and DSP-1 games
	
	References:
	- http://old.smwiki.net/wiki/Internal_ROM_Header
	- https://en.wikibooks.org/wiki/Super_NES_Programming/SNES_memory_map
	- https://patpend.net/technical/snes/sneskart.html
]]

-- Module table
local v2proto = {}

-- Import required modules
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local snes = require "scripts.app.snes"
local apperase = require "scripts.app.erase"

-- Constants
local HIROM_NAME = 'HiROM'
local LOROM_NAME = 'LoROM'

-- Delay constants (in seconds)
local DELAY_BANK_SWITCH = 0.01
local DELAY_CHIP_STOP = 0.02
local DELAY_REGISTER_SETUP = 0.1

-- Hardware type lookup table
local hardware_type = {
	[0x00] = "ROM Only",
	[0x01] = "ROM and RAM",
	[0x02] = "ROM and Save RAM",
	[0x03] = "ROM and DSP1",
	[0x04] = "ROM, RAM and DSP1 chip",
	[0x05] = "ROM, Save RAM and DSP1 chip",
	[0x13] = "ROM and SuperFX", -- Star Fox (GSU-1, no SRAM)
	[0x15] = "ROM and SuperFX and Save RAM",
	[0x19] = "ROM and Super FX chip",
	[0x1A] = "ROM and SuperFX and Save RAM (Stunt Race FX)",
	[0x20] = "ROM Only (Third-party)",
	[0x21] = "ROM and RAM (Third-party)",
	[0x30] = "ROM Only (Majesco)",
	[0x31] = "ROM and RAM (Majesco)",
	[0x33] = "ROM and SA-1",
	[0x43] = "ROM and S-DD1",
	[0xF3] = "ROM and CX4",
	[0xF6] = "ROM and DSP2 chip",
}

--[[
	TODO: Investigate these configurations.
	4   ROM, RAM and DSP1 chip
	5   ROM, Save RAM and DSP1 chip
	19  ROM and Super FX chip
	227 ROM, RAM and GameBoy data
	246 ROM and DSP2 chip
	0x001A -> Stunt Race FX
	0x00F3 -> Megaman X2, X3
	0x0043 -> SF Alpha 2
]]

-- ROM size upper bound descriptions (actual program size may be smaller)
local rom_ubound = {
	[0x08] = "2 megabits",
	[0x09] = "4 megabits",
	[0x0A] = "8 megabits",
	[0x0B] = "16 megabits",
	[0x0C] = "32 megabits",
	[0x0D] = "64 megabits",
}

-- ROM size lookup table (converts header value to KB)
local rom_size_kb_tbl = {
	[0x08] = 256,   -- 2 megabits = 256 KB
	[0x09] = 512,   -- 4 megabits = 512 KB
	[0x0A] = 1024,  -- 8 megabits = 1024 KB (1 MB)
	[0x0B] = 2048,  -- 16 megabits = 2048 KB (2 MB)
	[0x0C] = 4096,  -- 32 megabits = 4096 KB (4 MB)
	[0x0D] = 8192,  -- 64 megabits = 8192 KB (8 MB)
}

-- SRAM size descriptions
local ram_size_tbl = {
	[0x00] = "No SRAM",
	[0x01] = "16 kilobits",
	[0x02] = "32 kilobits",
	[0x03] = "64 kilobits",
	[0x05] = "256 kilobits",
	[0x06] = "512 kilobits"
}

-- SRAM size lookup table (converts header value to KB)
local ram_size_kb_tbl = {
	[0x00] = 0,
	[0x01] = 2,   -- 16 kilobits = 2 KB
	[0x02] = 4,   -- 32 kilobits = 4 KB
	[0x03] = 8,   -- 64 kilobits = 8 KB
	[0x05] = 32,  -- 256 kilobits = 32 KB
	[0x06] = 64   -- 512 kilobits = 64 KB
}

-- Map mode descriptions
local map_mode_desc = {
	[0x00] = "LoROM SlowROM",
	[0x01] = "HiROM SlowROM",
	[0x02] = "LoROM SlowROM + SRAM",
	[0x03] = "HiROM SlowROM + SRAM",
	[0x10] = "LoROM SlowROM + SRAM",
	[0x11] = "HiROM SlowROM + SRAM",
	[0x12] = "LoROM SlowROM + SRAM",
	[0x13] = "HiROM SlowROM + SRAM",
	[0x20] = "LoROM FastROM",
	[0x21] = "HiROM FastROM",
	[0x22] = "LoROM SlowROM",
	[0x23] = "HiROM SlowROM",
	[0x24] = "LoROM FastROM",
	[0x25] = "ExHiROM FastROM",
	[0x30] = "LoROM FastROM",
	[0x31] = "HiROM FastROM",
	[0x32] = "LoROM FastROM",
	[0x34] = "LoROM FastROM"
}

-- Destination/region code lookup
local destination_code = {
	[0] = "Japan (NTSC)",
	[1] = "USA (NTSC)",
	[2] = "Australia, Europe, Oceania and Asia (PAL)",
	[3] = "Sweden (PAL)",
	[4] = "Finland (PAL)",
	[5] = "Denmark (PAL)",
	[6] = "France (PAL)",
	[7] = "Holland (PAL)",
	[8] = "Spain (PAL)",
	[9] = "Germany, Austria and Switzerland (PAL)",
	[10] = "Italy (PAL)",
	[11] = "Hong Kong and China (PAL)",
	[12] = "Indonesia (PAL)",
	[13] = "Korea (PAL)",
}

-- Developer/manufacturer code lookup
local developer_code = {
	[0x01] = 'Nintendo',
	[0x03] = 'Imagineer-Zoom',
	[0x05] = 'Zamuse',
	[0x06] = 'Falcom',
	[0x08] = 'Capcom',
	[0x09] = 'HOT-B',
	[0x0a] = 'Jaleco',
	[0x0b] = 'Coconuts',
	[0x0c] = 'Rage Software',
	[0x0e] = 'Technos',
	[0x0f] = 'Mebio Software',
	[0x12] = 'Gremlin Graphics',
	[0x13] = 'Electronic Arts',
	[0x15] = 'COBRA Team',
	[0x16] = 'Human/Field',
	[0x17] = 'KOEI',
	[0x18] = 'Hudson Soft',
	[0x1a] = 'Yanoman',
	[0x1c] = 'Tecmo',
	[0x1e] = 'Open System',
	[0x1f] = 'Virgin Games',
	[0x20] = 'KSS',
	[0x21] = 'Sunsoft',
	[0x22] = 'POW',
	[0x23] = 'Micro World',
	[0x26] = 'Enix',
	[0x27] = 'Loriciel/Electro Brain',
	[0x28] = 'Kemco',
	[0x29] = 'Seta Co.,Ltd.',
	[0x2d] = 'Visit Co.,Ltd.',
	[0x31] = 'Carrozzeria',
	[0x32] = 'Dynamic',
	[0x33] = 'Nintendo',
	[0x34] = 'Magifact',
	[0x35] = 'Hect',
	[0x3c] = 'Empire Software',
	[0x3d] = 'Loriciel',
	[0x40] = 'Seika Corp.',
	[0x41] = 'UBI Soft',
	[0x46] = 'System 3',
	[0x47] = 'Spectrum Holobyte',
	[0x49] = 'Irem',
	[0x4b] = 'Raya Systems/Sculptured Software',
	[0x4c] = 'Renovation Products',
	[0x4d] = 'Malibu Games/Black Pearl',
	[0x4f] = 'U.S. Gold',
	[0x50] = 'Absolute Entertainment',
	[0x51] = 'Acclaim',
	[0x52] = 'Activision',
	[0x53] = 'American Sammy',
	[0x54] = 'GameTek',
	[0x55] = 'Hi Tech Expressions',
	[0x56] = 'LJN Toys',
	[0x5a] = 'Mindscape',
	[0x5d] = 'Tradewest',
	[0x5f] = 'American Softworks Corp.',
	[0x60] = 'Titus',
	[0x61] = 'Virgin Interactive Entertainment',
	[0x62] = 'Maxis',
	[0x67] = 'Ocean',
	[0x69] = 'Electronic Arts',
	[0x6b] = 'Laser Beam',
	[0x6e] = 'Elite',
	[0x6f] = 'Electro Brain',
	[0x70] = 'Infogrames',
	[0x71] = 'Interplay',
	[0x72] = 'LucasArts',
	[0x73] = 'Parker Brothers',
	[0x75] = 'STORM',
	[0x78] = 'THQ Software',
	[0x79] = 'Accolade Inc.',
	[0x7a] = 'Triffix Entertainment',
	[0x7c] = 'Microprose',
	[0x7f] = 'Kemco',
	[0x80] = 'Misawa',
	[0x81] = 'Teichio',
	[0x82] = 'Namco Ltd.',
	[0x83] = 'Lozc',
	[0x84] = 'Koei',
	[0x86] = 'Tokuma Shoten Intermedia',
	[0x88] = 'DATAM-Polystar',
	[0x8b] = 'Bullet-Proof Software',
	[0x8c] = 'Vic Tokai',
	[0x8e] = 'Character Soft',
	[0x8f] = 'I\'\'Max',
	[0x90] = 'Takara',
	[0x91] = 'CHUN Soft',
	[0x92] = 'Video System Co., Ltd.',
	[0x93] = 'BEC',
	[0x95] = 'Varie',
	[0x97] = 'Kaneco',
	[0x99] = 'Pack in Video',
	[0x9a] = 'Nichibutsu',
	[0x9b] = 'TECMO',
	[0x9c] = 'Imagineer Co.',
	[0xa0] = 'Telenet',
	[0xa4] = 'Konami',
	[0xa5] = 'K.Amusement Leasing Co.',
	[0xa7] = 'Takara',
	[0xa9] = 'Technos Jap.',
	[0xaa] = 'JVC',
	[0xac] = 'Toei Animation',
	[0xad] = 'Toho',
	[0xaf] = 'Namco Ltd.',
	[0xb1] = 'ASCII Co. Activison',
	[0xb2] = 'BanDai America',
	[0xb4] = 'Enix',
	[0xb6] = 'Halken',
	[0xba] = 'Culture Brain',
	[0xbb] = 'Sunsoft',
	[0xbc] = 'Toshiba EMI',
	[0xbd] = 'Sony Imagesoft',
	[0xbf] = 'Sammy',
	[0xc0] = 'Taito',
	[0xc2] = 'Kemco',
	[0xc3] = 'Square',
	[0xc4] = 'Tokuma Soft',
	[0xc5] = 'Data East',
	[0xc6] = 'Tonkin House',
	[0xc8] = 'KOEI',
	[0xca] = 'Konami USA',
	[0xcb] = 'NTVIC',
	[0xcd] = 'Meldac',
	[0xce] = 'Pony Canyon',
	[0xcf] = 'Sotsu Agency/Sunrise',
	[0xd0] = 'Disco/Taito',
	[0xd1] = 'Sofel',
	[0xd2] = 'Quest Corp.',
	[0xd3] = 'Sigma',
	[0xd6] = 'Naxat',
	[0xd8] = 'Capcom Co., Ltd.',
	[0xd9] = 'Banpresto',
	[0xda] = 'Tomy',
	[0xdb] = 'Acclaim',
	[0xdd] = 'NCS',
	[0xde] = 'Human Entertainment',
	[0xdf] = 'Altron',
	[0xe0] = 'Jaleco',
	[0xe2] = 'Yutaka',
	[0xe4] = 'T&ESoft',
	[0xe5] = 'EPOCH Co.,Ltd.',
	[0xe7] = 'Athena',
	[0xe8] = 'Asmik',
	[0xe9] = 'Natsume',
	[0xea] = 'King Records',
	[0xeb] = 'Atlus',
	[0xec] = 'Sony Music Entertainment',
	[0xee] = 'IGS',
	[0xf1] = 'Motown Software',
	[0xf2] = 'Left Field Entertainment',
	[0xf3] = 'Beam Software',
	[0xf4] = 'Tec Magik',
	[0xf9] = 'Cybersoft',
	[0xff] = 'Hudson Soft',
}

--[[
	Utility Functions
]]

--- Format a value as a hexadecimal string
-- @param val The value to format
-- @return Formatted hex string (e.g., "0x1234")
function hexfmt(val)
	return string.format("0x%04X", val)
end

--- Check if a string is empty or nil
-- @param s String to check
-- @return true if string is nil or empty
local function isempty(s)
	return s == nil or s == ""
end

--- Read a sequence of bytes from ROM
-- @param base_addr Starting address
-- @param n Number of bytes to read
-- @return Table of byte values (1-indexed)
function seq_read(base_addr, n)
	local rv = {}
	for count = 1, n do
		rv[count] = dict.snes("SNES_ROM_RD", base_addr + count - 1)
	end
	return rv
end

--- Extract a null-terminated string from ROM data
-- @param base_addr Starting address in ROM
-- @param length Maximum length to read
-- @return Extracted string (trimmed)
function string_from_bytes(base_addr, length)
	local byte_table = seq_read(base_addr, length)
	local s = ""
	
	for count = 1, length do
		local byte_val = byte_table[count]
		
		-- Stop at null terminator
		if byte_val == 0x00 then
			break
		end
		
		-- Filter printable characters (0x20-0xFF)
		-- Replace control characters with space
		if byte_val >= 0x20 and byte_val <= 0xFF then
			s = s .. string.char(byte_val)
		elseif byte_val < 0x20 then
			s = s .. " "
		end
	end
	
	-- Trim trailing spaces
	return s:match("^%s*(.-)%s*$") or s
end

--- Read a 16-bit word from two consecutive bytes (big-endian)
-- @param base_addr Starting address
-- @return 16-bit word value
function word_from_two_bytes(base_addr)
	local upper = dict.snes("SNES_ROM_RD", base_addr) << 8
	local lower = dict.snes("SNES_ROM_RD", base_addr + 1)
	return upper | lower
end

--[[
	Header Parsing Functions
]]

--- Print formatted ROM header information
-- @param internal_header Header table from get_header()
function print_header(internal_header)
	-- Get descriptive map mode name
	local map_mode_str = map_mode_desc[internal_header["map_mode"]]
	if not map_mode_str then
		local map_mode_base = LOROM_NAME
		if (internal_header["map_mode"] & 1) == 1 then
			map_mode_base = HIROM_NAME
		end
		map_mode_str = map_mode_base .. " - " .. hexfmt(internal_header["map_mode"])
	end

	-- Get hardware type description
	local rom_type_str = "UNKNOWN - " .. hexfmt(internal_header["rom_type"])
	if hardware_type[internal_header["rom_type"]] then
		rom_type_str = hardware_type[internal_header["rom_type"]]
	end

	-- Get ROM size description
	local rom_size_str = "UNKNOWN - " .. hexfmt(internal_header["rom_size"])
	if rom_ubound[internal_header["rom_size"]] then
		rom_size_str = rom_ubound[internal_header["rom_size"]]
	end

	-- Get SRAM size description
	local sram_size_str = "UNKNOWN - " .. hexfmt(internal_header["sram_size"])
	if ram_size_tbl[internal_header["sram_size"]] then
		sram_size_str = ram_size_tbl[internal_header["sram_size"]]
	end

	-- Get expansion RAM size description
	local exp_size_str = "No Expansion RAM"
	if ram_size_tbl[internal_header["exp_ram_size"]] then
		exp_size_str = ram_size_tbl[internal_header["exp_ram_size"]]
	end

	-- Get destination/region description
	local destination_code_str = "UNKNOWN - " .. hexfmt(internal_header["destination_code"])
	if destination_code[internal_header["destination_code"]] then
		destination_code_str = destination_code[internal_header["destination_code"]]
	end

	-- Get developer description
	local developer_code_str = "UNKNOWN - " .. hexfmt(internal_header["developer_code"])
	if developer_code[internal_header["developer_code"]] then
		developer_code_str = developer_code[internal_header["developer_code"]]
	end

	-- Print header information
	print("Rom Title:\t\t" .. internal_header["rom_name"])
	print("Map Mode:\t\t" .. map_mode_str)
	print("Hardware Type:\t\t" .. rom_type_str)
	print("Rom Size Upper Bound:\t" .. rom_size_str)
	print("SRAM Size:\t\t" .. sram_size_str)
	print("Expansion RAM Size:\t" .. exp_size_str)
	print("Destination Code:\t" .. destination_code_str)
	print("Developer:\t\t" .. developer_code_str)
	print("Version:\t\t" .. string.format("%d.%.1d", (internal_header["version"] or 0) >> 4, (internal_header["version"] or 0) & 0x0F))
	print("Checksum:\t\t" .. hexfmt(internal_header["checksum"]))
end

--- Read and parse SNES ROM header
-- @param map_adjust Address adjustment for mapping mode (0x0000 for HiROM, 0x8000 for LoROM)
-- @return Table containing parsed header fields
function get_header(map_adjust)
	local mapping = "unknown"
	
	-- ROM Registration Addresses (15 bytes)
	local addr_maker_code = 0xFFB0 - map_adjust             -- 2 bytes
	local addr_game_code = 0xFFB2 - map_adjust              -- 4 bytes
	local addr_fixed_zero = 0xFFB6 - map_adjust             -- 7 bytes
	local addr_expansion_ram_size = 0xFFBD - map_adjust     -- 1 byte
	local addr_special_version_code = 0xFFBE - map_adjust   -- 1 byte

	-- ROM Specification Addresses (32 bytes)
	local addr_rom_name = 0xFFC0 - map_adjust           -- 21 bytes
	local addr_map_mode = 0xFFD5 - map_adjust           -- 1 byte
	local addr_rom_type = 0xFFD6 - map_adjust           -- 1 byte
	local addr_rom_size = 0xFFD7 - map_adjust           -- 1 byte
	local addr_sram_size = 0xFFD8 - map_adjust          -- 1 byte
	local addr_destination_code = 0xFFD9 - map_adjust   -- 1 byte
	local addr_developer_code = 0xFFDA - map_adjust     -- 1 byte (manufacturer ID)
	local addr_version = 0xFFDB - map_adjust            -- 1 byte
	local addr_compliment_check = 0xFFDC - map_adjust   -- 2 bytes
	local addr_checksum = 0xFFDD - map_adjust           -- 2 bytes

	local internal_header = {
		mapping = mapping,
		rom_name = string_from_bytes(addr_rom_name, 21),
		map_mode = dict.snes("SNES_ROM_RD", addr_map_mode),
		rom_type = dict.snes("SNES_ROM_RD", addr_rom_type),
		rom_size = dict.snes("SNES_ROM_RD", addr_rom_size),
		sram_size = dict.snes("SNES_ROM_RD", addr_sram_size),
		exp_ram_size = dict.snes("SNES_ROM_RD", addr_expansion_ram_size),  -- Expansion RAM for GSU games
		destination_code = dict.snes("SNES_ROM_RD", addr_destination_code),
		developer_code = dict.snes("SNES_ROM_RD", addr_developer_code),
		version = dict.snes("SNES_ROM_RD", addr_version),
		compliment_check = word_from_two_bytes(addr_compliment_check),
		checksum = word_from_two_bytes(addr_checksum)
	}
	return internal_header
end

--- Determine mapping mode from map mode byte
-- @param map_mode_byte Map mode byte from header
-- @return "HiROM" or "LoROM" string
function mappingfrommapmode(map_mode_byte)
	local is_hirom = (map_mode_byte & 1) > 0
	
	-- Special handling for map mode 0x44 (SHVC-2J3M-11 PCB games like Robotrek, Brain Lord)
	-- These are HiROM but bit 0 is 0, causing incorrect LoROM detection
	-- Bit 4 set with bits 6-7 indicating FastROM variant
	if map_mode_byte == 0x44 then
		return HIROM_NAME
	end
	
	if is_hirom then
		return HIROM_NAME
	else
		return LOROM_NAME
	end
end

--- Validate ROM header by checking essential fields
-- @param internal_header Header table to validate
-- @param debug Enable debug output
-- @return true if header appears valid
function isvalidheader(internal_header, debug)
	-- Check if header is nil or empty
	if not internal_header then
		if debug then
			print("Header is nil")
		end
		return false
	end
	
	-- Check for all 0xFF values (unmapped/invalid memory)
	-- This indicates we're reading from the wrong bank or cartridge isn't responding
	-- Also check checksum and complement check - if both are 0xFFFF, likely invalid
	if (internal_header["rom_type"] == 0xFF and 
	    internal_header["rom_size"] == 0xFF and 
	    internal_header["map_mode"] == 0xFF) or
	   (internal_header["checksum"] == 0xFFFF and 
	    internal_header["compliment_check"] == 0xFFFF) then
		if debug then
			print("Rejecting header - all values are 0xFF or checksum/complement are 0xFFFF (unmapped memory)")
		end
		return false
	end
	
	-- Relaxed validation - only check essential fields
	-- Many proto/odd carts omit or corrupt optional fields like checksum
	local valid_rom_type = hardware_type[internal_header["rom_type"]] ~= nil
	local valid_rom_size = (internal_header["rom_size"] ~= nil) and
	                      (rom_size_kb_tbl[internal_header["rom_size"]] ~= nil)
	
	if debug then
		print("ROM type = 0x" .. string.format("%02X", internal_header["rom_type"] or 0xFF) .. 
		      " (valid: " .. tostring(valid_rom_type) .. ")")
		print("ROM size = 0x" .. string.format("%02X", internal_header["rom_size"] or 0xFF) .. 
		      " (valid: " .. tostring(valid_rom_size) .. ")")
		print("ROM name = '" .. (internal_header["rom_name"] or "") .. "'")
		print("Map mode = 0x" .. string.format("%02X", internal_header["map_mode"] or 0xFF))
	end
	
	-- Check if ROM name has actual printable characters (not just spaces or control chars)
	local rom_name = internal_header["rom_name"] or ""
	local has_readable_name = false
	if rom_name ~= "" then
		-- Check if name contains at least 3 printable ASCII characters (0x20-0x7E)
		local printable_count = 0
		for i = 1, math.min(21, string.len(rom_name)) do
			local byte = string.byte(rom_name, i)
			if byte and byte >= 0x20 and byte <= 0x7E then
				printable_count = printable_count + 1
			end
		end
		has_readable_name = printable_count >= 3
	end
	
	-- If ROM type or size is invalid, but we have a readable ROM name, accept it anyway
	-- This helps with carts that have non-standard header values but are otherwise valid
	if not valid_rom_type or not valid_rom_size then
		if has_readable_name then
			if debug then
				print("Accepting header with readable ROM name despite invalid type/size")
			end
			return true
		end
		if debug then
			print("Rejecting header - invalid type/size and no readable ROM name")
		end
		return false
	end
	
	return true
end

--- Test cartridge and read header information
-- @return Header table if valid header found, nil otherwise
function test()
	-- Ensure cartridge is in play mode (not reset) for proper ROM access
	snes.play_mode()
	
	-- Small delay to ensure cartridge is ready
	local t0 = os.clock()
	while os.clock() - t0 < DELAY_REGISTER_SETUP do end
	
	-- Try reading headers with multiple bank configurations
	-- Try HiROM banks first since many games use HiROM
	local hirom_header = nil
	local lorom_header = nil
	local internal_header = nil
	
	-- First attempt: Try HiROM banks (most common for larger games)
	-- Try HiROM at bank 0x80 (FastROM) first - most common for commercial games
	print("Attempting HiROM FastROM detection (bank 0x80)...")
	dict.snes("SNES_SET_BANK", 0x80)
	hirom_header = get_header(0x0000)
	
	if isvalidheader(hirom_header, true) then
		print("Valid header found at HiROM FastROM address.")
		print("")
		internal_header = hirom_header
	else
		-- Try HiROM header at bank 0xC0 (SlowROM)
		print("Attempting HiROM SlowROM detection (bank 0xC0)...")
		dict.snes("SNES_SET_BANK", 0xC0)
		hirom_header = get_header(0x0000)
		
		if isvalidheader(hirom_header, true) then
			print("Valid header found at HiROM SlowROM address.")
			print("")
			internal_header = hirom_header
		else
			-- Try LoROM header read
			print("Attempting LoROM detection (bank 0x00)...")
			dict.snes("SNES_SET_BANK", 0x00)
			lorom_header = get_header(0x8000)
			
			if isvalidheader(lorom_header, true) then
				print("Valid header found at LoROM address.")
				print("")
				internal_header = lorom_header
			end
		end
	end
	
	-- If header read failed, try retry with longer delays
	if not internal_header then
		print("Retrying with longer delays...")
		-- Reset and try again with longer delays
		snes.play_mode()
		t0 = os.clock()
		while os.clock() - t0 < DELAY_REGISTER_SETUP * 2 do end
		
		-- Retry HiROM FastROM
		print("Retry: HiROM FastROM detection (bank 0x80)...")
		dict.snes("SNES_SET_BANK", 0x80)
		hirom_header = get_header(0x0000)
		
		if isvalidheader(hirom_header, true) then
			print("Valid header found at HiROM FastROM address (retry).")
			print("")
			internal_header = hirom_header
		else
			-- Retry HiROM SlowROM
			print("Retry: HiROM SlowROM detection (bank 0xC0)...")
			dict.snes("SNES_SET_BANK", 0xC0)
			hirom_header = get_header(0x0000)
			
			if isvalidheader(hirom_header, true) then
				print("Valid header found at HiROM SlowROM address (retry).")
				print("")
				internal_header = hirom_header
			else
				-- Retry LoROM
				print("Retry: LoROM detection (bank 0x00)...")
				dict.snes("SNES_SET_BANK", 0x00)
				lorom_header = get_header(0x8000)
				
				if isvalidheader(lorom_header, true) then
					print("Valid header found at LoROM address (retry).")
					print("")
					internal_header = lorom_header
				end
			end
		end
	end
	
	if internal_header then
		internal_header["mapping"] = mappingfrommapmode(internal_header["map_mode"])
	else
		print("Could not parse internal ROM header.")
		print("Please check:")
		print("  - Cartridge is properly inserted")
		print("  - Cartridge pins are clean")
		print("  - Cartridge works on a real console")
		print("  - Try reseating the cartridge")
	end
	
	return internal_header
end

--[[
	Flash ROM Functions
]]

--[[
	Flash ROM Functions
]]

--- Attempt to read flash ROM manufacturer/product ID
-- @param debug Enable debug output
-- @return true if proper flash ID found
local function rom_manf_id(debug)
	-- Enter software mode for ID read
	dict.snes("SNES_SET_BANK", 0x00)
	
	-- Send unlock sequence: WR $AAA:AA $555:55 $AAA:AA
	dict.snes("SNES_ROM_WR", 0x8AAA, 0xAA)
	dict.snes("SNES_ROM_WR", 0x8555, 0x55)
	dict.snes("SNES_ROM_WR", 0x8AAA, 0x90)
	
	-- Read manufacturer ID (0x01 = Cypress)
	local manf_id = dict.snes("SNES_ROM_RD", 0x8000)
	if debug then
		print("attempted read SNES ROM manf ID:", string.format("%X", manf_id))
	end
	
	-- Read product ID (0x7E = S29GL, 0x49 = 2MB variant)
	local prod_id = dict.snes("SNES_ROM_RD", 0x8002)
	if debug then
		print("attempted read SNES ROM prod ID:", string.format("%X", prod_id))
	end
	
	local density_id = dict.snes("SNES_ROM_RD", 0x801C)
	if debug then
		print("attempted read SNES density ID: ", string.format("%X", density_id))
	end
	
	local boot_sect = dict.snes("SNES_ROM_RD", 0x801E)
	if debug then
		print("attempted read SNES boot sect ID:", string.format("%X", boot_sect))
	end
	
	-- Exit software mode
	dict.snes("SNES_ROM_WR", 0x8000, 0xF0)
	
	-- Validate detected flash chip
	if (manf_id == 0x01 and prod_id == 0x49) then
		print("2MB flash detected")
		return true
	elseif (manf_id == 0x01 and prod_id == 0x7E) then
		print("4-8MB flash detected")
		return true
	else
		return false
	end
end

--- Erase flash ROM chip
-- @param debug Enable debug output
local function erase_flash(debug)
	print("\nErasing TSSOP flash takes about 30sec...")
	
	dict.snes("SNES_SET_BANK", 0x00)
	
	-- Send chip erase sequence: WR $AAA:AA $555:55 $AAA:AA $AAA:AA $555:55 $AAA:AA
	dict.snes("SNES_ROM_WR", 0x8AAA, 0xAA)
	dict.snes("SNES_ROM_WR", 0x8555, 0x55)
	dict.snes("SNES_ROM_WR", 0x8AAA, 0x80)
	dict.snes("SNES_ROM_WR", 0x8AAA, 0xAA)
	dict.snes("SNES_ROM_WR", 0x8555, 0x55)
	dict.snes("SNES_ROM_WR", 0x8AAA, 0x10)
	
	-- Wait for erase to complete (check for 0xFF)
	local rv = dict.snes("SNES_ROM_RD", 0x8000)
	local i = 0
	
	while (rv ~= 0xFF) do
		rv = dict.snes("SNES_ROM_RD", 0x8000)
		i = i + 1
	end
	
	print(i, "naks, done erasing Super Nintendo.")
	
	-- Reset flash
	dict.snes("SNES_ROM_WR", 0x8000, 0xF0)
end

--[[
	Special Chip Functions
]]

--- Stop the GSU (SuperFX) chip to ensure clean ROM access
-- GSU needs to be stopped before ROM dumping to prevent interference
-- @param debug Enable debug output
-- @param mapping "HiROM" or "LoROM"
local function stop_gsu_chip(debug, mapping)
	if debug then
		print("Stopping GSU chip for ROM dump...")
	end
	
	-- GSU registers are at $3000-$32FF
	-- LoROM: banks $30-$32
	-- HiROM: banks $C0-$C2
	local gsu_bank = 0x30  -- Default to LoROM
	if mapping == HIROM_NAME then
		gsu_bank = 0xC0  -- HiROM GSU register space
	end
	
	-- Access GSU registers
	dict.snes("SNES_SET_BANK", gsu_bank)
	
	-- Stop the GSU processor (clear GO bit in control register $3030)
	local control_reg = dict.snes("SNES_ROM_RD", 0x3030)
	dict.snes("SNES_ROM_WR", 0x3030, control_reg & 0x7F)  -- Clear bit 7 (GO)
	
	-- Wait for processor to stop
	local t0 = os.clock()
	while os.clock() - t0 < DELAY_CHIP_STOP do end
	
	-- Set SCMR (Screen Mode Control Register) for ROM access
	dict.snes("SNES_ROM_WR", 0x3033, 0x00)
	
	-- Enable ROM access (RON) and disable RAM access (RAN)
	control_reg = dict.snes("SNES_ROM_RD", 0x3030)
	dict.snes("SNES_ROM_WR", 0x3030, (control_reg | 0x40) & 0xEF)  -- Set bit 6 (RON), clear bit 4 (RAN)
	
	-- Wait for writes to complete
	t0 = os.clock()
	while os.clock() - t0 < DELAY_CHIP_STOP do end
	
	if debug then
		print("GSU chip stopped and ROM access enabled")
	end
end

--- Detect if game uses SuperFX (GSU-1) chip
-- @param internal_header Header table
-- @param rom_title ROM title string
-- @return true if SuperFX chip detected
local function is_superfx_game(internal_header, rom_title)
	-- Check header hardware type
	if internal_header and internal_header["rom_type"] then
		local hw = hardware_type[internal_header["rom_type"]] or ""
		if string.find(hw, "SuperFX") or string.find(hw, "Super FX") or string.find(hw, "GSU") then
			return true
		end
	end
	
	-- Check ROM title for known SuperFX games
	if rom_title then
		if string.find(rom_title, "STUNT RACE") or string.find(rom_title, "STUNT RACER") then
			return true
		end
	end
	
	return false
end

--[[
	ROM Dumping Functions
]]

--- Dump SNES ROM to file
-- /ROMSEL is always low for this dump
-- @param file File handle to write to
-- @param start_bank Starting bank number
-- @param rom_size_KB ROM size in kilobytes
-- @param mapping "HiROM" or "LoROM"
-- @param debug Enable debug output
-- @param internal_header Header table for special case handling
local function dump_rom(file, start_bank, rom_size_KB, mapping, debug, internal_header)
	-- Default to LoROM if mapping not set
	if not mapping or mapping == "" then
		mapping = LOROM_NAME
		if debug then
			print("Mapping not set in dump_rom, defaulting to LoROM")
		end
	end

	-- Validate ROM size
	if rom_size_KB == nil or rom_size_KB <= 0 then
		print("ERROR: ROM size unknown; cannot dump.")
		return
	end

	local KB_per_bank
	local addr_base

	-- Determine bank size and base address based on mapping
	if mapping == LOROM_NAME then
		KB_per_bank = 32  -- LoROM has 32KB per bank
		addr_base = 0x80  -- $8000 LoROM
	elseif mapping == HIROM_NAME then
		-- Special case: LoROM FastROM games detected as HiROM
		-- Check if map mode indicates LoROM FastROM (0x20, 0x22, 0x24, etc.)
		if internal_header and internal_header["map_mode"] and
		   (internal_header["map_mode"] & 0xF0) == 0x20 and
		   (internal_header["map_mode"] & 0x01) == 0 then
			-- This is actually LoROM FastROM - use LoROM settings
			KB_per_bank = 32
			addr_base = 0x80
			if debug then
				print("Detected LoROM FastROM game, using LoROM addresses")
			end
		else
			KB_per_bank = 64  -- HiROM has 64KB per bank
			addr_base = 0x00  -- $0000 HiROM
		end
	else
		print("ERROR!! mapping:", mapping, "not supported")
		return
	end
	
	local num_reads = rom_size_KB / KB_per_bank
	local read_count = 0
	
	-- Dump each bank
	while read_count < num_reads do
		if read_count % 8 == 0 then
			print("Dumping ROM bank: ", read_count, " of ", num_reads - 1)
		end

		local current_bank = start_bank + read_count
		dict.snes("SNES_SET_BANK", current_bank)
		
		-- Dump this bank
		dump.dumptofile(file, KB_per_bank, addr_base, "SNESROM_PAGE", false)

		read_count = read_count + 1
	end
end

--[[
	SRAM Dumping Functions
]]

--- Check if game is EarthBound (Mother 2)
-- @param rom_title ROM title string
-- @return true if EarthBound detected
local function is_earthbound_game(rom_title)
	if not rom_title or rom_title == "" then
		return false
	end
	
	local rom_title_upper = string.upper(rom_title)
	-- Check for "EARTH" and "BOUND" combination, or "MOTHER" (Japanese name)
	return (string.find(rom_title_upper, "EARTH") and string.find(rom_title_upper, "BOUND")) or
	       string.find(rom_title_upper, "MOTHER")
end

--- Dump EarthBound SRAM (special handling required)
-- @param file File handle to write to
-- @param start_bank Starting bank (overridden to 0x30)
local function dump_earthbound_sram(file, start_bank)
	-- EarthBound uses bank 0x30, offset 0x0060, SNESSYS_PAGE, 8KB SRAM
	-- Note: offset 0x0060 (96 decimal) is different from standard HiROM 0x6000
	print("Earthbound detected - using special SRAM dump (bank 0x30, offset 0x0060, SNESSYS_PAGE, 8KB)")
	
	dict.snes("SNES_SET_BANK", 0x30)
	
	local t0 = os.clock()
	while os.clock() - t0 < DELAY_CHIP_STOP do end
	
		dump.dumptofile(file, 8, 0x0060, "SNESSYS_PAGE", false)
	file:flush()
end

--- Check if game is SimEarth
-- @param rom_title ROM title string
-- @return true if SimEarth detected
local function is_simearth_game(rom_title)
	if not rom_title or rom_title == "" then
		return false
	end
	
	local rom_title_upper = string.upper(rom_title)
	return string.find(rom_title_upper, "SIM") and string.find(rom_title_upper, "EARTH")
end

--- Check if game is Soul Blazer
-- @param rom_title ROM title string
-- @return true if Soul Blazer detected
local function is_soulblazer_game(rom_title)
	if not rom_title or rom_title == "" then
		return false
	end
	
	local rom_title_upper = string.upper(rom_title)
	return string.find(rom_title_upper, "SOUL") and string.find(rom_title_upper, "BLAZER")
end

--- Post-process Soul Blazer SRAM dump to extract active save slot
-- Hardware dump format differs from emulator format
-- Search for the save slot signature pattern and extract it
-- @param ram_filename Path to the SRAM dump file
local function postprocess_soulblazer_sram(ram_filename)
	local file = io.open(ram_filename, "rb")
	if not file then
		print("Soul Blazer: Could not reopen SRAM file for post-processing")
		return
	end
	
	local raw_data = file:read("*all")
	file:close()
	
	local file_size = #raw_data
	if file_size < 512 then
		print("Soul Blazer: SRAM file too small for post-processing")
		return
	end
	
	-- Emulator format starts with: 04 06 06 04 08 03...
	-- Hardware dump typically has FF at position 1, then 04 at position 2
	-- Simple check: if byte 1 is FF and byte 2 is 04, extract from byte 2
	local found_offset = nil
	
	if file_size >= 2 and string.byte(raw_data, 1) == 0xFF and string.byte(raw_data, 2) == 0x04 then
		found_offset = 2
		print("Soul Blazer: Detected FF prefix, extracting from offset 0x01")
	else
		-- Search for the pattern as fallback
		local pattern_start = {0x04, 0x06, 0x06, 0x04, 0x08, 0x03}
		for i = 1, file_size - #pattern_start do
			local match = true
			for j = 1, #pattern_start do
				if string.byte(raw_data, i + j - 1) ~= pattern_start[j] then
					match = false
					break
				end
			end
			if match then
				found_offset = i
				print("Soul Blazer: Found save slot pattern at offset 0x" .. string.format("%X", found_offset - 1))
				break
			end
		end
	end
	
	if found_offset then
		print("Soul Blazer: Found save slot pattern at offset 0x" .. string.format("%X", found_offset - 1))
		-- Verify first byte is 0x04
		local first_byte = string.byte(raw_data, found_offset)
		if first_byte ~= 0x04 then
			print("Soul Blazer: WARNING - Pattern match but first byte is 0x" .. string.format("%02X", first_byte) .. " (expected 0x04)")
		end
		
		-- Extract from found offset to end - this is the save slot data
		local save_slot_data = string.sub(raw_data, found_offset)
		
		-- Verify extracted data starts with 0x04
		local extracted_first = string.byte(save_slot_data, 1)
		print("Soul Blazer: Extracted data starts with 0x" .. string.format("%02X", extracted_first))
		
		-- Write the corrected format: save slot at start, pad rest with zeros
		file = io.open(ram_filename, "wb")
		if not file then
			print("Soul Blazer: Could not rewrite SRAM file")
			return
		end
		
		file:write(save_slot_data)
		
		-- Pad to original file size if needed
		if #save_slot_data < file_size then
			local padding = string.rep("\x00", file_size - #save_slot_data)
			file:write(padding)
		end
		
		file:close()
		
		-- Verify the written file
		file = io.open(ram_filename, "rb")
		if file then
			local verify_data = file:read(1)
			file:close()
			if verify_data then
				local verify_byte = string.byte(verify_data, 1)
				print("Soul Blazer: Written file starts with 0x" .. string.format("%02X", verify_byte))
			end
		end
		
		print("Soul Blazer: Post-processed SRAM dump (extracted save slot from offset 0x" .. string.format("%X", found_offset - 1) .. ", wrote " .. #save_slot_data .. " bytes)")
		
		-- Also check for save data signature "PG" (50 47) which should appear later in the file
		local pg_pattern = {0x50, 0x47}
		local pg_offset = nil
		for i = 1, file_size - 1 do
			if string.byte(raw_data, i) == pg_pattern[1] and string.byte(raw_data, i + 1) == pg_pattern[2] then
				pg_offset = i
				print("Soul Blazer: Found save data signature 'PG' at offset 0x" .. string.format("%X", pg_offset - 1))
				break
			end
		end
	else
		print("Soul Blazer: Could not find save slot signature pattern in SRAM dump")
		-- Fallback: if dump starts with FF 06, prepend 04 to match emulator format
		if file_size >= 2 and string.byte(raw_data, 1) == 0xFF and string.byte(raw_data, 2) == 0x06 then
			local corrected_data = string.char(0x04) .. string.sub(raw_data, 2)
			-- Ensure file is exactly 8192 bytes (8KB) - truncate if longer, pad if shorter
			local target_size = 8192
			if #corrected_data > target_size then
				corrected_data = string.sub(corrected_data, 1, target_size)
			elseif #corrected_data < target_size then
				corrected_data = corrected_data .. string.rep("\x00", target_size - #corrected_data)
			end
			file = io.open(ram_filename, "wb")
			if file then
				file:write(corrected_data)
				file:close()
				print("Soul Blazer: Fallback - prepended 0x04 byte, file size: " .. #corrected_data .. " bytes")
				
				-- Check where save data appears in corrected file
				local pg_pattern = {0x50, 0x47}
				for i = 1, #corrected_data - 1 do
					if string.byte(corrected_data, i) == pg_pattern[1] and string.byte(corrected_data, i + 1) == pg_pattern[2] then
						print("Soul Blazer: Save data 'PG' signature found at offset 0x" .. string.format("%X", i - 1) .. " in corrected file")
						break
					end
				end
			end
		elseif string.byte(raw_data, 1) == 0xFF then
			-- Just remove FF if second byte isn't 06
			local corrected_data = string.sub(raw_data, 2)
			file = io.open(ram_filename, "wb")
			if file then
				file:write(corrected_data)
				if #corrected_data < file_size then
					file:write(string.rep("\x00", file_size - #corrected_data))
				end
				file:close()
				print("Soul Blazer: Fallback - removed leading FF byte")
			end
		end
	end
end

--- Enable LoROM SRAM banks by programming the MAD-1 register
-- Some SHVC-1A5B-0x boards keep SRAM disabled until bits are set at $A13000/$A13001
-- @param ram_size_KB Total SRAM size requested
local function enable_lorom_sram(ram_size_KB)
	local effective_size = ram_size_KB or 0
	if effective_size <= 0 then
		effective_size = 8 -- default to a single 8KB window so we at least get one bank
	end

	-- Each bit represents an 8KB window across banks $70-$7F (SNES dev manual, MAD-1)
	local total_windows = math.max(1, math.ceil(effective_size / 8))
	if total_windows > 16 then
		total_windows = 16 -- hardware only exposes banks $70-$7F
	end

	local lower_mask = 0
	local upper_mask = 0

	for window = 0, total_windows - 1 do
		if window < 8 then
			lower_mask = lower_mask | (1 << window)
		else
			upper_mask = upper_mask | (1 << (window - 8))
		end
	end

	-- $A13000 controls banks $70-$77, $A13001 controls $78-$7F
	dict.snes("SNES_SET_BANK", 0xA1)
	dict.snes("SNES_SYS_WR", 0x3000, lower_mask)
	dict.snes("SNES_SYS_WR", 0x3001, upper_mask)
end

--- Dump SimEarth SRAM (requires TOMCAT signature search)
-- @param file File handle to write to
-- @param debug Enable debug output
local function dump_simearth_sram(file, debug)
	print("Dumping SRAM bank 0 of 0 (bank 0x70, offset 0x0000, 8KB, LoROM)")

	-- Make sure MAD-1 exposes SRAM before we try to scan for TOMCAT
	enable_lorom_sram(8)
	
	dict.snes("SNES_SET_BANK", 0x70)
	
	local t0 = os.clock()
	while os.clock() - t0 < DELAY_BANK_SWITCH do end
	
	-- Read full 32KB window to search for TOMCAT signature
	local search_file = io.open("simearth_search.bin", "wb")
	if not search_file then
		-- Fallback if file creation fails
		print("Dumping SRAM bank 0 of 0 (bank 0x70, offset 0x6000, 8KB, LoROM)")
		dict.snes("SNES_SET_BANK", 0x70)
		t0 = os.clock()
		while os.clock() - t0 < DELAY_BANK_SWITCH do end
		dump.dumptofile(file, 8, 0x6000, "SNESROM_PAGE", false)
		return
	end
	
	dump.dumptofile(search_file, 32, 0x0000, "SNESROM_PAGE", false)
	search_file:close()
	
	local read_search = io.open("simearth_search.bin", "rb")
	if not read_search then
		-- Fallback if file read fails
		os.remove("simearth_search.bin")
		print("Dumping SRAM bank 0 of 0 (bank 0x70, offset 0x6000, 8KB, LoROM)")
		dict.snes("SNES_SET_BANK", 0x70)
		t0 = os.clock()
		while os.clock() - t0 < DELAY_BANK_SWITCH do end
		dump.dumptofile(file, 8, 0x6000, "SNESROM_PAGE", false)
		return
	end
	
	local search_data = read_search:read("*all")
	read_search:close()
	os.remove("simearth_search.bin")
	
	-- Search for TOMCAT signature: 54 4F 4D 43 41 54
	local tomcat_pattern = {0x54, 0x4F, 0x4D, 0x43, 0x41, 0x54}
	local tomcat_pos = nil
	
	for i = 1, math.min(32768 - 6, #search_data - 5) do
		local match = true
		for j = 1, 6 do
			if string.byte(search_data, i + j - 1) ~= tomcat_pattern[j] then
				match = false
				break
			end
		end
		if match then
			tomcat_pos = i - 1  -- 0-indexed position
			break
		end
	end
	
	if tomcat_pos then
		-- Extract exactly 8KB starting from TOMCAT signature position
		local sram_data = string.sub(search_data, tomcat_pos + 1, tomcat_pos + 8192)
		
		if #sram_data == 8192 then
			file:write(sram_data)
		else
			if debug then
				print("SimEarth: WARNING - Expected 8192 bytes but got " .. #sram_data)
			end
			file:write(sram_data)
		end
	else
		-- Fallback to offset 0x6000 if TOMCAT not found
		print("Dumping SRAM bank 0 of 0 (bank 0x70, offset 0x6000, 8KB, LoROM)")
		dict.snes("SNES_SET_BANK", 0x70)
		t0 = os.clock()
		while os.clock() - t0 < DELAY_BANK_SWITCH do end
		dump.dumptofile(file, 8, 0x6000, "SNESROM_PAGE", false)
	end
end

--- Dump SNES SRAM to file
-- Currently supports LoROM boards where /ROMSEL maps to RAM space
-- @param file File handle to write to
-- @param start_bank Starting bank number
-- @param ram_size_KB SRAM size in kilobytes
-- @param mapping "HiROM" or "LoROM"
-- @param debug Enable debug output
-- @param rom_title ROM title for special game detection
-- @param internal_header Header table for special game detection
local function dump_ram(file, start_bank, ram_size_KB, mapping, debug, rom_title, internal_header, ram_filename)
	-- Early exit if no RAM to dump
	if ram_size_KB == nil or ram_size_KB == 0 then
		if debug then
			print("No SRAM to dump - ram_size_KB is 0")
		end
		return
	end
	
	-- Special handling for EarthBound (Mother 2)
	if is_earthbound_game(rom_title) then
		dump_earthbound_sram(file, start_bank)
		return
	end
	
	-- Special handling for SimEarth
	if is_simearth_game(rom_title) then
		dump_simearth_sram(file, debug)
		return
	end
	
	-- Standard SRAM dump
	local is_soulblazer = is_soulblazer_game(rom_title)
	local KB_per_bank
	local addr_base
	
	-- Determine bank size and base address based on mapping
	if mapping == LOROM_NAME then
		enable_lorom_sram(ram_size_KB)
		KB_per_bank = 8   -- LoROM SRAM uses 8KB per bank window
		addr_base = 0x00  -- $0000 LoROM RAM start address
	elseif mapping == HIROM_NAME then
		KB_per_bank = 8   -- HiROM has 8KB per bank
		addr_base = 0x60  -- $6000 HiROM RAM start address
	else
		print("ERROR! mapping:", mapping, "not supported by dump_ram")
		return
	end
	
	-- Calculate number of banks
	local num_banks
	if ram_size_KB < KB_per_bank then
		num_banks = 1
		KB_per_bank = ram_size_KB
	else
		num_banks = math.ceil(ram_size_KB / KB_per_bank)
	end
	
	-- Ensure num_banks is valid
	if not num_banks or num_banks < 1 then
		num_banks = 1
	end
	
	-- Dump each bank
	local read_count = 0
	while read_count < num_banks do
		if read_count == 0 or read_count % 8 == 0 or num_banks == 1 then
			local addr_str = string.format("0x%04X", addr_base)
			local map_type = (mapping == LOROM_NAME) and "LoROM" or "HiROM"
			print("Dumping SRAM bank ", read_count, " of ", math.max(0, num_banks - 1),
			      " (bank 0x" .. string.format("%02X", start_bank + read_count) ..
			      ", offset " .. addr_str .. ", " .. KB_per_bank .. "KB, " .. map_type .. ")")
		end

		local current_bank = start_bank + read_count
		dict.snes("SNES_SET_BANK", current_bank)
		
		-- Small delay to ensure bank switch completes
		local t0 = os.clock()
		while os.clock() - t0 < DELAY_BANK_SWITCH do end

		-- Dump based on mapping
		if mapping == LOROM_NAME then
			-- LoROM SRAM is inside /ROMSEL space
			dump.dumptofile(file, KB_per_bank, addr_base, "SNESROM_PAGE", false)
		else
			-- HiROM is outside of /ROMSEL space
			dump.dumptofile(file, KB_per_bank, addr_base, "SNESSYS_PAGE", false)
		end

		read_count = read_count + 1
	end
	
	-- Post-process Soul Blazer SRAM if needed
	if is_soulblazer and ram_filename then
		file:flush()
		postprocess_soulblazer_sram(ram_filename)
	end
end

--[[
	Flash Programming Functions
]]

--- Program flash ROM from file
-- TODO: Need to specify first bank, just like dumping!
-- @param file File handle to read from
-- @param rom_size_KB ROM size in kilobytes
-- @param mapping "HiROM" or "LoROM"
-- @param debug Enable debug output
local function flash_rom(file, rom_size_KB, mapping, debug)
	print("\nProgramming ROM flash")

	local base_addr
	local bank_size
	
	-- Determine base address and bank size based on mapping
	if mapping == LOROM_NAME then
		base_addr = 0x8000  -- Writes occur $8000-FFFF
		bank_size = 32 * 1024  -- SNES LoROM 32KB per ROM bank
	elseif mapping == HIROM_NAME then
		base_addr = 0x0000  -- Writes occur $0000-FFFF
		bank_size = 64 * 1024  -- SNES HiROM 64KB per ROM bank
	else
		print("ERROR!! mapping:", mapping, "not supported")
		return
	end

	local total_banks = rom_size_KB * 1024 / bank_size
	local cur_bank = 0

	while cur_bank < total_banks do
		if cur_bank % 4 == 0 then
			print("writting ROM bank: ", cur_bank, " of ", total_banks - 1)
		end

		-- Select the current bank (cannot exceed 0xFF)
		if cur_bank <= 0xFF then
			dict.snes("SNES_SET_BANK", cur_bank)
		else
			print("\n\nERROR!!!!  Super Nintendo bank cannot exceed 0xFF, it was:", string.format("0x%X", cur_bank))
			return
		end

		-- Program the entire bank's worth of data
		if mapping == LOROM_NAME then
			flash.write_file(file, bank_size / 1024, "LOROM_3VOLT", "SNESROM", false)
		else
			flash.write_file(file, bank_size / 1024, "HIROM_3VOLT", "SNESROM", false)
		end

		cur_bank = cur_bank + 1
	end

	print("Done Programming ROM flash")
end

--- Write SRAM from file
-- @param file File handle to read from
-- @param first_bank First bank number
-- @param ram_size_KB SRAM size in kilobytes
-- @param mapping "HiROM" or "LoROM"
-- @param debug Enable debug output
local function wr_ram(file, first_bank, ram_size_KB, mapping, debug)
	print("\nProgramming RAM")

	local base_addr
	local bank_size
	
	-- Determine base address and bank size based on mapping
	if mapping == LOROM_NAME then
		bank_size = 32 * 1024  -- LoROM has 32KB per bank
		base_addr = 0x0000     -- $0000 LoROM RAM start address
	elseif mapping == HIROM_NAME then
		bank_size = 8 * 1024   -- HiROM has 8KB per bank
		base_addr = 0x6000     -- $6000 HiROM RAM start address
	else
		print("ERROR! mapping:", mapping, "not supported by dump_ram")
		return
	end

	-- Calculate number of banks
	local total_banks
	if ram_size_KB * 1024 < bank_size then
		total_banks = 1
		bank_size = ram_size_KB * 1024
	else
		total_banks = ram_size_KB * 1024 / bank_size
	end

	local cur_bank = 0
	local byte_num
	local byte_str, data

	while cur_bank < total_banks do
		print("writting RAM bank: ", cur_bank, " of ", total_banks - 1)

		-- Select the current bank (cannot exceed 0xFF)
		if cur_bank <= 0xFF then
			dict.snes("SNES_SET_BANK", cur_bank + first_bank)
		else
			print("\n\nERROR!!!!  Super Nintendo bank cannot exceed 0xFF, it was:", string.format("0x%X", cur_bank))
			return
		end

		-- Write each byte in the bank
		print("This is slow as molasses, but gets the job done")
		byte_num = 0
		while byte_num < bank_size do
			-- Read next byte from file
			byte_str = file:read(1)
			data = string.unpack("B", byte_str, 1)

			-- Write the data
			if mapping == LOROM_NAME then
				dict.snes("SNES_ROM_WR", base_addr + byte_num, data)
			else
				dict.snes("SNES_SYS_WR", base_addr + byte_num, data)
			end

			byte_num = byte_num + 1
		end

		cur_bank = cur_bank + 1
	end

	print("Done Programming RAM")
end

--[[
	Flash Programming Functions
]]

--- Write a single byte to SNES ROM flash
-- @param addr Address within current bank (0x0000-0xFFFF)
-- @param value Byte value to write
-- @param debug Enable debug output
local function wr_flash_byte(addr, value, debug)
	if addr < 0x0000 or addr > 0xFFFF then
		print("\n  ERROR! flash write to Super Nintendo", string.format("$%X", addr), "must be $0000-FFFF \n\n")
		return
	end

	-- Send unlock command sequence and write byte
	dict.snes("SNES_ROM_WR", 0x8AAA, 0xAA)
	dict.snes("SNES_ROM_WR", 0x8555, 0x55)
	dict.snes("SNES_ROM_WR", 0x8AAA, 0xA0)
	dict.snes("SNES_ROM_WR", addr, value)

	-- Verify write completed
	local rv = dict.snes("SNES_ROM_RD", addr)
	local i = 0

	while rv ~= value do
		rv = dict.snes("SNES_ROM_RD", addr)
		i = i + 1
	end
	
	if debug then
		print(i, "naks, done writing byte.")
		print("written value:", string.format("%X", value), "verified value:", string.format("%X", rv))
	end
end

--[[
	Main Process Function
]]

--- Main processing function - handles all cartridge operations
-- Cart should be in reset state upon calling this function
-- @param process_opts Table containing operation flags and filenames
-- @param console_opts Table containing console-specific options
local function process(process_opts, console_opts)
	-- Initialize device I/O for SNES
	dict.io("IO_RESET")
	dict.io("SNES_INIT")

	local internal_header = nil

	-- Get mapper setting (normalize to match constants)
	local snes_mapping = console_opts["mapper"]
	if snes_mapping then
		local lower = string.lower(snes_mapping)
		if lower == "hirom" then
			snes_mapping = HIROM_NAME
		elseif lower == "lorom" then
			snes_mapping = LOROM_NAME
		end
	end
	
	-- Initialize bank variables to defaults (LoROM)
	local rombank = 0x00
	local rambank = 0x70
	
	if snes_mapping == LOROM_NAME then
		-- LoROM typically sees the upper half (A15=1) of the first address 0b0000:1000_0000
		rombank = 0x00
		rambank = 0x70  -- LoROM maps from 0x70 to 0x7D
	elseif snes_mapping == HIROM_NAME then
		-- HiROM bank selection: default to 0x80 (fast ROM, first 4MB)
		rombank = 0x80  -- Fast ROM, first 4MB (correct for most HiROM games <= 4MB)
		rambank = 0x30
	end

	local dumpram = process_opts["dumpram"]
	local ramdumpfile = process_opts["dumpram_filename"]

	-- Get RAM and ROM sizes
	local ram_size = console_opts["wram_size_kb"]
	local rom_size = console_opts["rom_size_kbyte"]

	-- Test cartridge and read header
	if process_opts["test"] then
		print("")
		print("Testing Super Nintendo game cartridge.")
		internal_header = test()
		if internal_header then
			print_header(internal_header)
		end

		-- Autodetect missing parameters from header
		if isempty(snes_mapping) and internal_header then
			snes_mapping = internal_header["mapping"]
			if snes_mapping == LOROM_NAME then
				rombank = 0x00
				rambank = 0x70  -- LoROM maps from 0x70 to 0x7D
			elseif snes_mapping == HIROM_NAME then
				-- HiROM bank selection depends on ROM size
				local rom_size_kb = rom_size or (internal_header and rom_size_kb_tbl[internal_header["rom_size"]] or 0)
				if rom_size_kb and rom_size_kb <= 4096 then
					rombank = 0x80  -- First 4MB (fast ROM)
				else
					rombank = 0xC0  -- Second 4MB (fast ROM)
				end
				rambank = 0x30
			end
		end
	end

	-- Autodetect RAM size
	if (ram_size == 0 or ram_size == nil) and internal_header then
		-- For GSU-1 games, check expansion RAM field if SRAM size is 0
		local sram_table = ram_size_kb_tbl[internal_header["sram_size"]]
		local exp_ram_table = ram_size_kb_tbl[internal_header["exp_ram_size"]] or 0
		
		if (sram_table == 0) or (sram_table == nil) then
			if exp_ram_table > 0 then
				ram_size = exp_ram_table
				print("Save RAM Size not provided, " .. ram_size .. " kilobytes detected.")
			else
				ram_size = sram_table
			end
		else
			ram_size = sram_table
		end
		
		-- Special handling for SHVC-1A3B-13 PCB: header may report 8KB but actual SRAM is 64KB
		-- Check if this looks like SHVC-1A3B-13 (LoROM with SRAM, common games like Zelda, etc.)
		if snes_mapping == LOROM_NAME and ram_size == 8 and internal_header["rom_type"] then
			local hw_type = hardware_type[internal_header["rom_type"]] or ""
			if string.find(hw_type, "Save RAM") or string.find(hw_type, "RAM") then
				-- Many SHVC-1A3B-13 games report 8KB in header but have 64KB SRAM
				-- Try 64KB if header says 8KB and it's a LoROM game with SRAM
				print("Warning: Header reports 8KB SRAM, but SHVC-1A3B-13 PCB typically has 64KB.")
				print("Attempting to dump 64KB SRAM (will verify during dump)...")
				ram_size = 64
			end
		end
	end

	-- Autodetect ROM size
	if (rom_size == 0 or rom_size == nil) and internal_header then
		rom_size = rom_size_kb_tbl[internal_header["rom_size"]]
		-- Defensive fallback when header provides invalid/unknown ROM size
		if rom_size == nil or rom_size == 0 then
			rom_size = 1024  -- Default to 1MB if unknown
			print("ROM size in header is invalid/unknown - defaulting to 1024KB")
		end
	end

	-- Dump SRAM to file
	if dumpram then
		print("\nDumping SAVE RAM...")
		
		local file = assert(io.open(ramdumpfile, "wb"))
		local rom_title = internal_header and internal_header["rom_name"] or ""
		dump_ram(file, rambank, ram_size, snes_mapping, true, rom_title, internal_header, ramdumpfile)
		assert(file:close())
		
		print("Finished dumping Super Nintendo battery save data (SRAM).")
	end

	-- Dump ROM to file
	if process_opts["read"] then
		print("\nDumping Super Nintendo game ROM...")
		
		-- Initialize special chips if needed
		local rom_title = internal_header and internal_header["rom_name"] or ""
		if is_superfx_game(internal_header, rom_title) then
			stop_gsu_chip(true, snes_mapping)
		end

		local file = assert(io.open(process_opts["dump_filename"], "wb"))
		dump_rom(file, rombank, rom_size, snes_mapping, false, internal_header)
		assert(file:close())
		
		print("Finished dumping Super Nintendo game ROM.")
	end

	-- Erase flash ROM
	if process_opts["erase"] then
		erase_flash()
	end

	-- Write SRAM from file
	if process_opts["writeram"] then
		print("\nWriting to SAVE RAM...")
		
		local file = assert(io.open(process_opts["writeram_filename"], "rb"))
		wr_ram(file, rambank, ram_size, snes_mapping, true)
		assert(file:close())
		
		print("DONE Writing SAVE RAM")
	end

	-- Program flash ROM from file
	if process_opts["program"] then
		-- Note: flashfile variable should be defined in process_opts
		local flashfile = process_opts["flashfile"]
		if flashfile then
			local file = assert(io.open(flashfile, "rb"))
			flash_rom(file, rom_size, snes_mapping, true)
			assert(file:close())
		else
			print("ERROR: flashfile not specified")
		end
	end

	-- Verify flash ROM
	if process_opts["verify"] then
		print("\nPost dumping Super Nintendo ROM...")
		
		-- Initialize special chips if needed
		local rom_title = internal_header and internal_header["rom_name"] or ""
		if is_superfx_game(internal_header, rom_title) then
			stop_gsu_chip(true, snes_mapping)
		end

		local verifyfile = process_opts["verifyfile"]
		if verifyfile then
			local file = assert(io.open(verifyfile, "wb"))
			dump_rom(file, rombank, rom_size, snes_mapping, false, internal_header)
			assert(file:close())
			print("DONE Post dumping Super Nintendo ROM")
		else
			print("ERROR: verifyfile not specified")
		end
	end

	dict.io("IO_RESET")
end

--[[
	Module Exports
]]

-- Export process function for use by other modules
v2proto.process = process

-- Return the module table
return v2proto
