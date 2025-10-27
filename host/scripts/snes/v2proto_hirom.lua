
-- create the module's table
local v2proto = {}

-- import required modules
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local snes = require "scripts.app.snes"
local apperase = require "scripts.app.erase"

-- file constants
local hirom_name = 'HiROM'
local lorom_name = 'LoROM'

-- Useful References:
-- http://old.smwiki.net/wiki/Internal_ROM_Header
-- https://en.wikibooks.org/wiki/Super_NES_Programming/SNES_memory_map
-- https://patpend.net/technical/snes/sneskart.html

local hardware_type = {
    [0x00] = "ROM Only",
    [0x01] = "ROM and RAM",
    [0x02] = "ROM and Save RAM",
	[0x03] = "ROM and DSP1",
	[0x04] = "ROM, RAM and DSP1 chip",
    [0x05] = "ROM, Save RAM and DSP1 chip",
    [0x13] = "ROM and SuperFX",
    [0x15] = "ROM and SuperFX and Save RAM",
    [0x19] = "ROM and Super FX chip",
	[0x20] = "ROM Only (Third-party)",
	[0x21] = "ROM and RAM (Third-party)",
	[0x30] = "ROM Only (Majesco)",
	[0x31] = "ROM and RAM (Majesco)",
    [0x33] = "ROM and SA-1",
    [0x1A] = "ROM and SuperFX and Save RAM (Stunt Race FX)",
	[0x43] = "ROM and S-DD1",
	[0xF3] = "ROM and CX4",
	[0xF6] = "ROM and DSP2 chip",

}
--[[
	TODO: Investigate these configurations.
	4   ROM, RAM and DSP1 chip
	5   ROM, Save RAM and DSP1 chip
	19  ROM and Super FX chip
   227  ROM, RAM and GameBoy data
   246  ROM and DSP2 chip
   0x001A -> Stunt Race FX
   0x00F3 -> Megaman X2, X3
   0x0043 -> SF Alpha 2
--]]

-- Upperbound for ROM size, actual program size may be smaller.
local rom_ubound = {
    [0x08] = "2 megabits",
    [0x09] = "4 megabits",
    [0x0A] = "8 megabits",
    [0x0B] = "16 megabits",
    [0x0C] = "32 megabits",
    [0x0D] = "64 megabits",
}

-- Translates size in header to KBytes.
local rom_size_kb_tbl = {
    [0x08] = 2 * 128,
    [0x09] = 4 * 128,
    [0x0A] = 8 * 128,
    [0x0B] = 16 * 128,
    [0x0C] = 32 * 128,
    [0x0D] = 64 * 128,
}

local ram_size_tbl = {
    [0x00] = "No sram",
    [0x01] = "16 kilobits",
    [0x02] = "32 kilobits",
    [0x03] = "64 kilobits",
    [0x05] = "256 kilobits"
}

-- Translates ram size in header to KBytes.
local ram_size_kb_tbl = {
	[0x00] = 0,
    [0x01] = 2,
    [0x02] = 4,
    [0x03] = 8,
    [0x05] = 32
}

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

function hexfmt(val)
    return string.format("0x%04X", val)
end

local function isempty(s)
    return s == nil or s == ""
end

function seq_read(base_addr, n)
    local rv = {}
    local count = 0
    while (count < n) do
        local val = dict.snes("SNES_ROM_RD", base_addr + count)
        count = count + 1
        -- Kind of an ordering hack because Lua likes 1-based structures.
        rv[count] = val
    end
    return rv
end

function string_from_bytes(base_addr, length)
    local byte_table = seq_read(base_addr, length)
    local s = ""
    local count = 0
    while (count < length) do
        s = s .. string.char(byte_table[count + 1])
        count = count + 1
    end
    return s
end

function word_from_two_bytes(base_addr)
    local upper = dict.snes("SNES_ROM_RD", base_addr) << 8
    local lower = dict.snes("SNES_ROM_RD", base_addr + 1)
    return upper | lower
end

function print_header(internal_header)
    local map_mode_str = lorom_name
	if (internal_header["map_mode"] & 1) == 1 then map_mode_str = hirom_name end

	-- For each field, default to showing hex value so program doesn't crash if a value is unexpected.
	local rom_type_str = "UNKNOWN - " .. hexfmt(internal_header["rom_type"])
	if hardware_type[internal_header["rom_type"]] then rom_type_str = hardware_type[internal_header["rom_type"]] end

	local rom_size_str = "UNKNOWN - " .. hexfmt(internal_header["rom_size"])
	if rom_ubound[internal_header["rom_size"]] then rom_size_str = rom_ubound[internal_header["rom_size"]] end

	local sram_size_str = "UNKNOWN - " .. hexfmt(internal_header["sram_size"])
	if ram_size_tbl[internal_header["sram_size"]] then sram_size_str = ram_size_tbl[internal_header["sram_size"]] end

	local destination_code_str = "UNKNOWN - " .. hexfmt(internal_header["destination_code"])
	if destination_code[internal_header["destination_code"]] then
		destination_code_str = destination_code[internal_header["destination_code"]]
	end

	local developer_code_str = "UNKNOWN - " .. hexfmt(internal_header["developer_code"])
	if developer_code[internal_header["developer_code"]] then
		developer_code_str = developer_code[internal_header["developer_code"]]
	end

	print("Rom Title:\t\t" .. internal_header["rom_name"])
    print("Map Mode:\t\t" .. map_mode_str .. " - " .. hexfmt(internal_header["map_mode"]))
    print("Hardware Type:\t\t" .. rom_type_str)
    print("Rom Size Upper Bound:\t" .. rom_size_str)
    print("SRAM Size:\t\t" .. sram_size_str)
    print("Destination Code:\t" .. destination_code_str)
    print("Developer:\t\t" .. developer_code_str)
    print("Version:\t\t" .. hexfmt(internal_header["version"]))
    print("Checksum:\t\t" ..  hexfmt(internal_header["checksum"]))
end

function get_header(map_adjust)
	local mapping = "unknown"
    -- Rom Registration Addresses (15 bytes)
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
    local addr_developer_code = 0xFFDA - map_adjust     -- 1 byte (This is actually manufacturer ID)
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
        destination_code = dict.snes("SNES_ROM_RD", addr_destination_code),
        developer_code = dict.snes("SNES_ROM_RD", addr_developer_code),
        version = dict.snes("SNES_ROM_RD", addr_version),
        compliment_check = word_from_two_bytes(addr_compliment_check),
        checksum = word_from_two_bytes(addr_checksum)
    }
    return internal_header
end

function mappingfrommapmode(map_mode_byte)
	local is_hirom = (map_mode_byte & 1) > 0
	if is_hirom then return hirom_name
	else return lorom_name
	end
end

function isvalidheader(internal_header)
	-- Spot check a few fields.
	-- TODO: Check more/all fields, look for printable name?
	local valid_rom_type = hardware_type[internal_header["rom_type"]]
	local valid_destination_code = destination_code[internal_header["destination_code"]]
    return valid_rom_type and internal_header["rom_size"] and internal_header["sram_size"] and valid_destination_code
end

function test()
	local hirom_header = get_header(0x0000)
	local lorom_header = get_header(0x8000)
	local internal_header = nil
	if isvalidheader(hirom_header) then
		print("Valid header found at HiROM address.")
		internal_header = hirom_header
	elseif isvalidheader(lorom_header) then
		print("Valid header found at LoROM address.")
		internal_header = lorom_header
	end
	if internal_header then
		internal_header["mapping"] = mappingfrommapmode(internal_header["map_mode"])
	else
		print("Could not parse internal ROM header.")
	end
	return internal_header
end

-- local functions


-- Desc: attempt to read flash rom ID
-- Pre: snes_init() been called to setup i/o
-- Post:Address left on bus memories disabled
-- Rtn: true if proper flash ID found
local function rom_manf_id( debug )

	local rv
	--enter software mode A11 is highest address bit that needs to be valid
	--datasheet not exactly explicit, A11 might not need to be valid
	--part has A-1 (negative 1) since it's in byte mode, meaning the part's A11 is actually A12
	--WR $AAA:AA $555:55 $AAA:AA
	dict.snes("SNES_SET_BANK", 0x00)

	dict.snes("SNES_ROM_WR", 0x8AAA, 0xAA)
	dict.snes("SNES_ROM_WR", 0x8555, 0x55)
	dict.snes("SNES_ROM_WR", 0x8AAA, 0x90)

	--read manf ID
	local manf_id = dict.snes("SNES_ROM_RD", 0x8000) --0x01 Cypress Manf ID
	if debug then print("attempted read SNES ROM manf ID:", string.format("%X", manf_id)) end

	--read prod ID
	local prod_id = dict.snes("SNES_ROM_RD", 0x8002) --0x7E Prod ID S29GL
	if debug then print("attempted read SNES ROM prod ID:", string.format("%X", prod_id)) end

	local density_id = dict.snes("SNES_ROM_RD", 0x801C) --density 0x10=8MB 0x1A=4MB
	if debug then print("attempted read SNES density ID: ", string.format("%X", density_id)) end

	local boot_sect = dict.snes("SNES_ROM_RD", 0x801E) --boot sector 0x00=top 0x01=bottom
	if debug then print("attempted read SNES boot sect ID:", string.format("%X", boot_sect)) end

	--exit software
	dict.snes("SNES_ROM_WR", 0x8000, 0xF0)

	--return true if detected flash chip
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



local function erase_flash( debug )

	local rv = nil

	print("\nErasing TSSOP flash takes about 30sec...");

	--WR $AAA:AA $555:55 $AAA:AA
	dict.snes("SNES_SET_BANK", 0x00)

	dict.snes("SNES_ROM_WR", 0x8AAA, 0xAA)
	dict.snes("SNES_ROM_WR", 0x8555, 0x55)
	dict.snes("SNES_ROM_WR", 0x8AAA, 0x80)
	dict.snes("SNES_ROM_WR", 0x8AAA, 0xAA)
	dict.snes("SNES_ROM_WR", 0x8555, 0x55)
	dict.snes("SNES_ROM_WR", 0x8AAA, 0x10)

	rv = dict.snes("SNES_ROM_RD", 0x8000)

	local i = 0

	while ( rv ~= 0xFF ) do
		rv = dict.snes("SNES_ROM_RD", 0x8000)
		i = i + 1
	--	if debug then print(" ", i,":", string.format("%x",rv)) end
	end
	print(i, "naks, done erasing snes.");

	--reset flash
	dict.snes("SNES_ROM_WR", 0x8000, 0xF0)
end


--dump the SNES ROM starting at the provided bank
--/ROMSEL is always low for this dump
local function dump_rom( file, start_bank, rom_size_KB, mapping, debug )

	-- If mapping is not set, default to LoROM
	if not mapping or mapping == "" then
		mapping = lorom_name
		if debug then print("Mapping not set in dump_rom, defaulting to LoROM") end
	end

	local KB_per_bank
	local addr_base

	if (mapping==lorom_name) then
		KB_per_bank = 32	-- LOROM has 32KB per bank
		addr_base = 0x80	-- $8000 LOROM
	elseif (mapping==hirom_name) then
		KB_per_bank = 64	-- HIROM has 64KB per bank
		addr_base = 0x00	-- $0000 HIROM
	else
		print("ERROR!! mapping:", mapping, "not supported")
		return
	end

	local num_reads = rom_size_KB / KB_per_bank
	local read_count = 0

	while ( read_count < num_reads ) do

		if debug then print( "dump ROM part ", read_count, " of ", num_reads) end

		if (read_count %8 == 0) then
			print("dumping ROM bank: ", read_count, " of ", num_reads-1)
		end

		--select desired bank
		dict.snes("SNES_SET_BANK", start_bank+read_count)

		dump.dumptofile( file, KB_per_bank, addr_base, "SNESROM_PAGE", debug )

		read_count = read_count + 1
	end

end

--dump the SNES RAM starting at the provided bank
--this is currently only for lorom boards where /ROMSEL maps to RAM space
local function dump_ram( file, start_bank, ram_size_KB, mapping, debug, rom_title, internal_header )

	-- If no RAM to dump, exit early
	if ram_size_KB == nil or ram_size_KB == 0 then
		if debug then print("No SRAM to dump - ram_size_KB is 0") end
		return
	end
	
	-- SA-1 BW-RAM handling: SA-1 games store save data in BW-RAM at banks $60-$6F
	local is_sa1 = false
	
	-- If mapping is not set, default to LoROM for SA-1 games
	if not mapping or mapping == "" then
		mapping = lorom_name
		if debug then print("Mapping not set, defaulting to LoROM for SA-1 detection") end
	end
	
	-- Check hardware type from header if available
	if internal_header and internal_header["rom_type"] then
		local hw = hardware_type[internal_header["rom_type"]] or ""
		if string.find(hw, "SA-1") then 
			is_sa1 = true
			if debug then print("SA-1 detected from header hardware type") end
		end
	end
	
	-- Check ROM title for SA-1 games (exclude DSP-1 games like Super Mario Kart)
	if not is_sa1 and rom_title and (
		string.find(rom_title, "Super Mario RPG") or 
		string.find(rom_title, "Mario RPG") or
		string.find(rom_title, "SMRPG")
	) then
		is_sa1 = true
		if debug then print("SA-1 detected from ROM title: " .. rom_title) end
	end
	
	-- Fallback heuristic: if a 32KB save was requested on LoROM, assume SA-1 BW-RAM
	-- BUT: Skip this for Yoshi's Island (standard LoROM SRAM) and DSP-1 games
	if not is_sa1 and mapping == lorom_name and ram_size_KB == 32 then
		-- Check if this is a DSP-1 game (like Super Mario Kart)
		local is_dsp1 = false
		if internal_header and internal_header["rom_type"] then
			local hw = hardware_type[internal_header["rom_type"]] or ""
			if string.find(hw, "DSP") then 
				is_dsp1 = true
				if debug then print("DSP-1 game detected - using standard LoROM SRAM, not SA-1 BW-RAM") end
			end
		end
		
		-- Check ROM title for DSP-1 games (fallback when header parsing fails)
		if not is_dsp1 and rom_title and (
			string.find(rom_title, "SUPER MARIO KART")
		) then
			is_dsp1 = true
			if debug then print("DSP-1 detected from ROM title: " .. rom_title) end
		end
		
		-- Check if this is Yoshi's Island - it uses standard LoROM SRAM, not SA-1 BW-RAM
		local is_yoshi = false
		if rom_title and (string.find(rom_title, "YOSHI") or string.find(rom_title, "SUPER MARIO WORLD 2")) then
			is_yoshi = true
			if debug then print("Yoshi's Island detected - using standard LoROM SRAM, not SA-1 BW-RAM") end
		end
		
		if not is_yoshi and not is_dsp1 then
			is_sa1 = true
			if debug then print("SA-1 assumed from 32KB LoROM save request") end
		end
	end
	
	-- Force Yoshi's Island to use standard LoROM SRAM
	if rom_title and (string.find(rom_title, "YOSHI") or string.find(rom_title, "SUPER MARIO WORLD 2")) then
		is_sa1 = false
		if debug then print("FORCE: Yoshi's Island detected - forcing standard LoROM SRAM") end
	end
	
	if debug then print("SA-1 FINAL: is_sa1=" .. tostring(is_sa1)) end
	
	-- Handle SA-1 BW-RAM dump
	if is_sa1 then
		if debug then print("SA-1 detected - dumping BW-RAM from banks $60-$63 at $6000 (total 32KB)") end
		
		-- SA-1 registers are accessible from SNES CPU at $2200-$22FF
		dict.snes("SNES_SET_BANK", 0x00)
		
		-- Small delay before accessing SA-1 registers
		local t0 = os.clock()
		while os.clock() - t0 < 0.02 do end
		
		if debug then print("SA-1: Setting up SA-1 registers for BW-RAM access") end
		
		-- Enable BW-RAM mapping and access
		dict.snes("SNES_SYS_WR", 0x2224, 0x80)  -- BMAPS: Enable BW-RAM mapping at $6000
		dict.snes("SNES_SYS_WR", 0x2226, 0x80)  -- SBWE: Enable SNES CPU write access
		
		-- Extended delay for register setup
		t0 = os.clock()
		while os.clock() - t0 < 0.1 do end
		
		-- Try accessing SA-1 registers from bank $30
		dict.snes("SNES_SET_BANK", 0x30)
		dict.snes("SNES_SYS_WR", 0x2224, 0x80)
		dict.snes("SNES_SYS_WR", 0x2226, 0x80)
		
		-- Read 32KB from banks $60-$63 at $6000-$7FFF
		for b = 0, 3 do
			local bank = 0x60 + b
			if debug then print("SA-1: Reading bank", string.format("0x%X", bank), "8KB @ $6000") end
			dict.snes("SNES_SET_BANK", bank)
			
			local t1 = os.clock()
			while os.clock() - t1 < 0.02 do end
			
			dump.dumptofile(file, 8, 0x6000, "SNESSYS_PAGE", false)
		end
		
		if debug then print("SA-1: BW-RAM dump completed (32KB total)") end
		return
	end

	local KB_per_bank
	local addr_base --A15-8 address of ram start

	--determine max ram per bank and base address
	if (mapping == lorom_name) then
		KB_per_bank = 32	-- LOROM has 32KB per bank
		addr_base = 0x00	-- $0000 LOROM RAM start address
	elseif (mapping == hirom_name) then
		KB_per_bank = 8		-- HIROM has 8KB per bank
		addr_base = 0x60	-- $6000 HIROM RAM start address
	else
		print("ERROR! mapping:", mapping, "not supported by dump_ram")
		return
	end

	local num_banks

	--determine how much ram to read per bank
    if ram_size_KB == nil then ram_size_KB = 0 end
	if KB_per_bank and (ram_size_KB < KB_per_bank) then
		num_banks = 1
		KB_per_bank = ram_size_KB
	else
		num_banks = ram_size_KB / KB_per_bank
	end

	local read_count = 0

	while ( read_count < num_banks ) do

		if debug then print( "dump ROM part ", read_count, " of ", num_banks) end

		--select desired bank
		dict.snes("SNES_SET_BANK", start_bank+read_count)

		if (mapping == lorom_name) then --LOROM sram is inside /ROMSEL space
			dump.dumptofile( file, KB_per_bank, addr_base, "SNESROM_PAGE", false )
		else -- HIROM is outside of /ROMSEL space
			dump.dumptofile( file, KB_per_bank, addr_base, "SNESSYS_PAGE", false )
		end

		read_count = read_count + 1
	end

end



--write a single byte to SNES ROM flash
--writes to currently selected bank address
local function wr_flash_byte(addr, value, debug)

	if (addr < 0x0000 or addr > 0xFFFF) then
		print("\n  ERROR! flash write to SNES", string.format("$%X", addr), "must be $0000-FFFF \n\n")
		return
	end

	--send unlock command and write byte
	dict.snes("SNES_ROM_WR", 0x8AAA, 0xAA)
	dict.snes("SNES_ROM_WR", 0x8555, 0x55)
	dict.snes("SNES_ROM_WR", 0x8AAA, 0xA0)
	dict.snes("SNES_ROM_WR", addr, value)

	local rv = dict.snes("SNES_ROM_RD", addr)

	local i = 0

	while ( rv ~= value ) do
		rv = dict.snes("SNES_ROM_RD", addr)
		i = i + 1
	end
	if debug then print(i, "naks, done writing byte.") end
	if debug then print("written value:", string.format("%X",value), "verified value:", string.format("%X",rv)) end

	--TODO handle timeout for problems

	--TODO return pass/fail/info
end


--fast host flash one bank at a time...
--this is controlled from the host side one bank at a time



--- TODO TODO TODO!!!  need to specific first bank!!!!   Just like dumping!
local function flash_rom(file, rom_size_KB, mapping, debug)

	print("\nProgramming ROM flash")

	--test some bytes
--	dict.snes("SNES_SET_BANK", 0x00) wr_flash_byte(0x8000, 0xA5, true) wr_flash_byte(0xFFFF, 0x5A, true)
--	dict.snes("SNES_SET_BANK", 0x01) wr_flash_byte(0x8000, 0x15, true) wr_flash_byte(0xFFFF, 0x1A, true)
	--last of 512KB
--	dict.snes("SNES_SET_BANK", 0x0F) wr_flash_byte(0x8000, 0xF5, true) wr_flash_byte(0xFFFF, 0xFA, true)

	--most of this is overkill for NROM, but it's how we want to handle things for bigger mappers
	local base_addr
	local bank_size
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0

	if (mapping==lorom_name) then
		base_addr = 0x8000 --writes occur $8000-FFFF
		bank_size = 32*1024 --SNES LOROM 32KB per ROM bank
	elseif (mapping==hirom_name) then
		base_addr = 0x0000 --writes occur $0000-FFFF
		bank_size = 64*1024 --SNES HIROM 64KB per ROM bank
	else
		print("ERROR!! mapping:", mapping, "not supported")
	end

	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata

	while cur_bank < total_banks do

		if (cur_bank %4 == 0) then
			print("writting ROM bank: ", cur_bank, " of ", total_banks-1)
		end

		--select the current bank
		if (cur_bank <= 0xFF) then
			dict.snes("SNES_SET_BANK", cur_bank)
		else
			print("\n\nERROR!!!!  SNES bank cannot exceed 0xFF, it was:", string.format("0x%X",cur_bank))
			return
		end

		--program the entire bank's worth of data

		--[[  This version of the code programs a single byte at a time but doesn't require
		--	board specific functions in the firmware
		print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware specific functions 100% host flash algo:
			--wr_flash_byte(base_addr+byte_num, data, false)   --0.7KBps
			--EASIEST FIRMWARE SPEEDUP: 5x faster, create firmware write byte function:
			dict.snes("FLASH_WR_3V", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)

			--if (verify) then
			--	readdata = dict.nes("NES_CPU_RD", base_addr+byte_num)
			--	if readdata ~= data then
			--		print("ERROR flashing byte number", byte_num, " in bank",cur_bank, " to flash ", data, readdata)
			--	end
			--end

			byte_num = byte_num + 1
		end
		--]]

		--Have the device write a banks worth of data
		if (mapping == lorom_name) then
			flash.write_file( file, bank_size/1024, "LOROM_3VOLT", "SNESROM", false )
		else
			flash.write_file( file, bank_size/1024, "HIROM_3VOLT", "SNESROM", false )
		end

		cur_bank = cur_bank + 1
	end

	print("Done Programming ROM flash")

end



local function wr_ram(file, first_bank, ram_size_KB, mapping, debug)

	print("\nProgramming RAM")

	--test some bytes
--	dict.snes("SNES_SET_BANK", 0x00) wr_flash_byte(0x8000, 0xA5, true) wr_flash_byte(0xFFFF, 0x5A, true)
--	dict.snes("SNES_SET_BANK", 0x01) wr_flash_byte(0x8000, 0x15, true) wr_flash_byte(0xFFFF, 0x1A, true)
	--last of 512KB
--	dict.snes("SNES_SET_BANK", 0x0F) wr_flash_byte(0x8000, 0xF5, true) wr_flash_byte(0xFFFF, 0xFA, true)

	local base_addr
	local bank_size
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata


	local addr_base --A15-8 address of ram start

	--determine max ram per bank and base address
	if (mapping == lorom_name) then
		bank_size = 32*1024	-- LOROM has 32KB per bank
		base_addr = 0x0000	-- $0000 LOROM RAM start address
	elseif (mapping == hirom_name) then
		bank_size = 8*1024	-- HIROM has 8KB per bank
		base_addr = 0x6000	-- $6000 HIROM RAM start address
	else
		print("ERROR! mapping:", mapping, "not supported by dump_ram")
	end

	local num_banks

	--determine how much ram to read per bank
	if (ram_size_KB*1024 < bank_size) then
		total_banks = 1
		bank_size = ram_size_KB*1024
	else
		total_banks = ram_size_KB*1024 / bank_size
	end

	while cur_bank < total_banks do

		print("writting RAM bank: ", cur_bank, " of ", total_banks-1)

		--select the current bank
		if (cur_bank <= 0xFF) then
			dict.snes("SNES_SET_BANK", cur_bank+first_bank)
		else
			print("\n\nERROR!!!!  SNES bank cannot exceed 0xFF, it was:", string.format("0x%X",cur_bank))
			return
		end

		--program the entire bank's worth of data

		---[[  This version of the code programs a single byte at a time but doesn't require
		--	board specific functions in the firmware
		print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware specific functions 100% host flash algo:
			--wr_flash_byte(base_addr+byte_num, data, false)   --0.7KBps
			--EASIEST FIRMWARE SPEEDUP: 5x faster, create firmware write byte function:
			--dict.snes("FLASH_WR_3V", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)
			if (mapping == lorom_name) then
				dict.snes("SNES_ROM_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)
			else
				dict.snes("SNES_SYS_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)
			end

			--if (verify) then
			--	readdata = dict.nes("NES_CPU_RD", base_addr+byte_num)
			--	if readdata ~= data then
			--		print("ERROR flashing byte number", byte_num, " in bank",cur_bank, " to flash ", data, readdata)
			--	end
			--end

			byte_num = byte_num + 1
		end
		--]]

		--Have the device write a banks worth of data
		--flash.write_file( file, bank_size/1024, "LOROM_3VOLT", "SNESROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming ROM flash")

end



--Cart should be in reset state upon calling this function
--this function processes all user requests for this specific board/mapper
local function process(process_opts, console_opts)
	local rv = nil
	local file

	--initialize device i/o for SNES
	dict.io("IO_RESET")
	dict.io("SNES_INIT")

	local internal_header = nil

	-- Use specified mapper if provided, otherwise autodetect.
	local snes_mapping = console_opts["mapper"]
	
	-- Initialize bank variables to defaults (LoROM)
	local rombank = 0x00
	local rambank = 0x70
	
	if (snes_mapping == lorom_name) then
		-- LOROM typically sees the upper half (A15=1) of the first address 0b0000:1000_0000
		rombank = 0x00
		rambank = 0x70 --LOROM maps from 0x70 to 0x7D
				--some for lower half of bank only, some for both halfs...
	elseif (snes_mapping == hirom_name) then
		-- HIROM typically sees the last 4MByte as the first addresses = 0b1100:0000_0000
		rombank = 0xC0
		--rombank = 0x40 --second HiROM bank (slow)
		rambank = 0x30
	end

	local dumpram = process_opts["dumpram"]
	local ramdumpfile = process_opts["dumpram_filename"]

	-- Use specified ram size if provided, otherwise autodetect.
	local ram_size = console_opts["wram_size_kb"]

	-- Use specified rom size if provided, otherwise autodetect.
	local rom_size = console_opts["rom_size_kbyte"]
	
	-- If header parsing failed and no sizes provided, set defaults for SA-1 games
	if not internal_header then
		if (ram_size == 0 or ram_size == nil) and dumpram then
			ram_size = 32  -- Default SA-1 SRAM size
			if debug then print("Header parsing failed - defaulting to 32KB SRAM for SA-1") end
		end
		if (rom_size == 0 or rom_size == nil) and process_opts["read"] then
			rom_size = 4096  -- Default 32Mbit (4MB) ROM for SA-1 games like Super Mario RPG
			if debug then print("Header parsing failed - defaulting to 4096KB ROM for SA-1") end
		end
	end



	-- TODO: Put this in a function.
	-- SNES memory map banking
	-- A15 always high for LOROM (A22 is typically low too)
	-- A22 always high for HIROM
	-- A23 splits the map in half
	-- A22 splits it in quarters (between what's typically low half and high half)
	-- b 7  6  5  4 :  3  2  1  0
	-- A23 22 21 20 : 19 18 17 16

--test cart by reading manf/prod ID
	if test then

		print("Testing SNES board");
		internal_header = test()
		if internal_header then
			print_header(internal_header)
		end

		-- Autodetect any missing parameters.
		if isempty(snes_mapping) and internal_header then
			snes_mapping = internal_header["mapping"]
			print("Mapping not provided, " .. snes_mapping .. " detected.")
			if (snes_mapping == lorom_name) then
				-- LOROM typically sees the upper half (A15=1) of the first address 0b0000:1000_0000
				rombank = 0x00
				rambank = 0x70 --LOROM maps from 0x70 to 0x7D
						--some for lower half of bank only, some for both halfs...
			elseif (snes_mapping == hirom_name) then
				-- HIROM typically sees the last 4MByte as the first addresses = 0b1100:0000_0000
				rombank = 0xC0
				--rombank = 0x40 --second HiROM bank (slow)
				rambank = 0x30
			end
		end

	if ((ram_size == 0) or (ram_size == nil)) and internal_header then
		ram_size = ram_size_kb_tbl[internal_header["sram_size"]]
            assert(ram_size, "SRAM Size unknown and not provided, please add ram size to console_opts")
			print("SRAM Size not provided, " .. ram_size_tbl[internal_header["sram_size"]] .. " detected.")
		end

	if ((rom_size == 0) or (rom_size == nil)) and internal_header then
		rom_size = rom_size_kb_tbl[internal_header["rom_size"]]
            assert(rom_size, "ROM Size unknown and not provided, please add rom size to console_opts")
			print("ROM Size not provided, " .. rom_ubound[internal_header["rom_size"]] .. " detected.")
		end

		--[[SNES detect if able to read flash ID's
		if not rom_manf_id(true) then
			print("ERROR unable to read flash ID")
			return
		end
		--]]
	end


--dump the ram to file
	if dumpram then

		print("\nDumping SAVE RAM...")

		--may have to verify /RESET is high to enable SRAM

		file = assert(io.open(ramdumpfile, "wb"))

		--dump cart into file
		local rom_title = internal_header and internal_header["rom_name"] or ""
		dump_ram(file, rambank, ram_size, snes_mapping, true, rom_title, internal_header)

		--may disable SRAM by placing /RESET low

		--close file
		assert(file:close())

		print("DONE Dumping SAVE RAM")
	end

--dump the cart to dumpfile
	if process_opts["read"] then
		print("\nDumping SNES ROM...")

		file = assert(io.open(process_opts["dump_filename"], "wb"))

		--dump cart into file
		dump_rom(file, rombank, rom_size, snes_mapping, false)

		--close file
		assert(file:close())
		print("DONE Dumping SNES ROM")
	end

--erase the cart
	if process_opts["erase"] then

		erase_flash()
	end

--write to wram on the cart
	if process_opts["writeram"] then

		print("\nWritting to SAVE RAM...")

		file = assert(io.open(process_opts["writeram_filename"], "rb"))

		--flash.write_file( file, ram_size, "NOVAR", "PRGRAM", false )
		--flash.write_file( file, ram_size, "LOROM_3VOLT", "SNESROM", false )
		wr_ram(file, rambank, ram_size, snes_mapping, true)

		--close file
		assert(file:close())

		print("DONE Writting SAVE RAM")
	end


--program flashfile to the cart
	if process_opts["program"] then

		--open file
		file = assert(io.open(flashfile, "rb"))
		--determine if auto-doubling, deinterleaving, etc,
		--needs done to make board compatible with rom

		--flash cart
		flash_rom(file, rom_size, snes_mapping, true)

		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if process_opts["verify"] then
		print("\nPost dumping SNES ROM...")
		--for now let's just dump the file and verify manually

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		dump_rom(file, rombank, rom_size, snes_mapping, false)

		--close file
		assert(file:close())
		print("DONE Post dumping SNES ROM")
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
v2proto.process = process

-- return the module's table
return v2proto
