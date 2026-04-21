
-- create the module's table
local n64 = {}

-- import required modules
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local help = require "scripts.app.help"
local inl_ui = require "scripts.app.inl_ui"

-- file constants

-- Common retail N64 ROM sizes (KiB), multiples of 128 KiB (1 Mbit). Used for mirror detection.
local CANDIDATE_ROM_KB = {
	4096, 6144, 8192, 12288, 16384, 20480, 24576, 28672,
	32768, 36864, 40960, 45056, 49152, 53248, 57344, 61440,
}

-- Retail ROM size by 4-byte game code at ROM offset 0x3B (ASCII, e.g. NPWE). Prefer this over
-- mirror detection: programmer bank decode can wrap (e.g. read at 32MiB aliases to 0).
-- Populated from host/data/n64-gameid.tsv (export from n64_roms_complete.xlsx).
local N64_ROM_KB_TSV_PATH = "data/n64-gameid.tsv"

local KNOWN_ROM_KB_BY_GAMECODE = {}

local function merge_n64_rom_kb_tsv(path, dest)
	local f = io.open(path, "rb")
	if not f then
		return
	end
	for line in f:lines() do
		local s = line:match("^%s*(.-)%s*$") or ""
		if s ~= "" and s:sub(1, 1) ~= "#" then
			local code, kb_s
			local tab = s:find("\t", 1, true)
			if tab then
				code = s:sub(1, tab - 1):match("^%s*(%S+)%s*$")
				kb_s = s:sub(tab + 1):match("^%s*(%d+)%s*$")
			else
				code, kb_s = s:match("^(%S+)%s+(%d+)%s*$")
			end
			if code and kb_s and #code == 4 then
				local kb = tonumber(kb_s)
				if kb and kb > 0 and kb % 128 == 0 then
					dest[code] = kb
				end
			end
		end
	end
	f:close()
end

merge_n64_rom_kb_tsv(N64_ROM_KB_TSV_PATH, KNOWN_ROM_KB_BY_GAMECODE)

-- IPL header: media category (first game-code character) and region (fourth character)
local N64_MEDIA_DESC = {
	N = "Nintendo 64 cartridge (Game Pak)",
	D = "64DD disk",
	C = "Expandable - Game Pak part",
	E = "Expandable - 64DD part",
	Z = "Aleck64 Game Pak",
}

local N64_REGION_DESC = {
	A = "All regions", B = "Brazil", C = "China", D = "Germany", E = "North America",
	F = "France", G = "Gateway 64 (NTSC)", ["H"] = "Netherlands", I = "Italy",
	J = "Japan", K = "Korea", L = "Gateway 64 (PAL)", N = "Canada", P = "Europe",
	S = "Spain", U = "Australia", W = "Scandinavia", X = "Europe", Y = "Europe",
	Z = "Europe",
}

-- local functions

local function be32(raw, idx)
	return (raw[idx] << 24) | (raw[idx + 1] << 16) | (raw[idx + 2] << 8) | raw[idx + 3]
end

local function title_from_bytes(raw, start_idx, len)
	local parts = {}
	for j = 0, len - 1 do
		local b = raw[start_idx + j]
		if b == nil or b == 0 then break end
		if b >= 0x20 and b <= 0x7E then
			parts[#parts + 1] = string.char(b)
		elseif b < 0x20 then
			parts[#parts + 1] = " "
		end
	end
	local s = table.concat(parts)
	return (s:match("^%s*(.-)%s*$") or s)
end

--[[
  Read 0x40 bytes from ROM offset 0 via sequential halfword reads (bank 0).
  1-based raw[] indexes: byte at ROM offset n is raw[n + 1].
--]]
local function read_n64_ipl_header()
	local bank_base = 0x1000
	dict.n64("N64_SET_BANK", bank_base + 0)
	dict.n64("N64_LATCH_ADDR", 0x0000)
	local raw = {}
	local i = 0
	while i < 0x40 do
		local rv = dict.n64("N64_RD")
		raw[i + 1] = (rv >> 8) & 0xFF
		raw[i + 2] = rv & 0xFF
		i = i + 2
	end
	dict.n64("N64_RELEASE_BUS")

	local gc = string.char(raw[0x3B + 1], raw[0x3C + 1], raw[0x3D + 1], raw[0x3E + 1])
	gc = gc:gsub("^%s+", ""):gsub("%s+$", "")

	local cc = {}
	for j = 0x10 + 1, 0x17 + 1 do
		cc[#cc + 1] = string.format("%02X", raw[j])
	end

	return {
		raw = raw,
		pi_config = be32(raw, 1),
		clock_rate = be32(raw, 5),
		boot_address = be32(raw, 9),
		libultra = { raw[13], raw[14], raw[15], raw[16] },
		check_code_hex = table.concat(cc),
		game_title = title_from_bytes(raw, 0x20 + 1, 20),
		game_code = gc,
		media_char = gc:sub(1, 1),
		region_char = gc:sub(4, 4),
		rom_version = raw[0x3F + 1] or 0,
	}
end

local function print_n64_header(hdr, use_color)
	local mc = hdr.media_char
	if mc == nil or mc == "" then mc = "?" end
	local rc = hdr.region_char
	if rc == nil or rc == "" then rc = "?" end
	local media_str = N64_MEDIA_DESC[mc] or ("UNKNOWN - 0x" .. string.format("%02X", string.byte(mc, 1)))
	local region_str = N64_REGION_DESC[rc] or ("UNKNOWN - " .. rc)
	local lu = hdr.libultra
	local lu_str = string.format("%02X %02X %02X %02X", lu[1] or 0, lu[2] or 0, lu[3] or 0, lu[4] or 0)

	inl_ui.print_kv("Rom Title", hdr.game_title, use_color)
	inl_ui.print_kv("Game Code", hdr.game_code, use_color)
	inl_ui.print_kv("Media Type", media_str, use_color)
	inl_ui.print_kv("Destination Code", region_str, use_color)
	inl_ui.print_kv("ROM Version", tostring(hdr.rom_version), use_color)
	inl_ui.print_kv("Boot Address", "0x" .. help.hex(hdr.boot_address), use_color)
	inl_ui.print_kv("Clock Rate", "0x" .. help.hex(hdr.clock_rate), use_color)
	inl_ui.print_kv("PI DOM1 Config", "0x" .. help.hex(hdr.pi_config), use_color)
	inl_ui.print_kv("Libultra Field", lu_str, use_color)
	inl_ui.print_kv("Check Code (IPL3)", hdr.check_code_hex, use_color)
end

-- Read an even number of bytes from cart ROM (big-endian halfwords via N64_RD).
local function read_rom_bytes(offset, nbytes)
	local bank_base = 0x1000
	assert(nbytes % 2 == 0, "read_rom_bytes length must be even")
	local buf = {}
	local n = 0
	while n < nbytes do
		local global_off = offset + n
		local bank = bank_base + (global_off // 65536)
		local addr = global_off % 65536
		dict.n64("N64_SET_BANK", bank)
		dict.n64("N64_LATCH_ADDR", addr)
		local rv = dict.n64("N64_RD")
		buf[#buf + 1] = (rv >> 8) & 0xFF
		buf[#buf + 1] = rv & 0xFF
		n = n + 2
	end
	dict.n64("N64_RELEASE_BUS")
	return buf
end

local function byte_tables_equal(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

-- True if ROM appears to repeat every s_kb KiB at several offsets (not only at 0).
-- Note: programmers often mirror high addresses into real ROM space. Larger "periods" can
-- then spuriously match (e.g. 32 MiB on an 8 MiB cart). We take the minimum size that
-- matches among all candidates; keep checks conservative (no half-span read) to avoid
-- false negatives on 8/16 MiB carts.
local MIRROR_CHECK_OFFSETS = { 0, 0x2000, 0x20000, 0x100000 }

local function mirror_period_matches(s_kb, sample)
	local span = s_kb * 1024
	for _, off in ipairs(MIRROR_CHECK_OFFSETS) do
		local a = read_rom_bytes(off, sample)
		local b = read_rom_bytes(span + off, sample)
		if not byte_tables_equal(a, b) then
			return false
		end
	end
	return true
end

-- FileAnalysis.psm1-style stats helpers (used by detect, post-dump analysis, ROM size display).
local function format_int_commas(n)
	local s = tostring(math.floor(n))
	local sign = ""
	if s:sub(1, 1) == "-" then
		sign = "-"
		s = s:sub(2)
	end
	local int, frac = s:match "^(%d+)(%.%d+)$"
	if not int then int = s end
	local out = ""
	while #int > 3 do
		out = "," .. int:sub(-3) .. out
		int = int:sub(1, -4)
	end
	return sign .. int .. out .. (frac or "")
end

local function round1(x)
	return math.floor(x * 10 + 0.5) / 10
end

-- Total time line: add "(N min, S seconds)" when over 60 seconds (matches PowerShell Process Summary).
local function format_total_time_sec(sec)
	if sec == nil or sec <= 0 then
		return nil
	end
	if sec <= 60 then
		return string.format("%.2f seconds", sec)
	end
	local mins = math.floor(sec / 60)
	local rem = sec - mins * 60
	return string.format("%.2f seconds (%d min, %.2f seconds)", sec, mins, rem)
end

--[[
  The 64-byte IPL header does not expose a trustworthy "ROM size in bytes" field for retail carts
  (see n64brew ROM header). Auto-size therefore uses, in order:
  1) Game code at 0x3B -> KNOWN_ROM_KB_BY_GAMECODE (from data/n64-gameid.tsv).
  2) Mirror heuristic (minimum of all candidate sizes that match); still wrong if only large periods match.
  3) 64 MiB fallback, or use explicit -k / -z from the host when you know the good dump size.

  Host policy: source/inlprog.c allows rom_size_kbyte == 0 for console n64 only (omit -k or -k 0).
--]]
-- @param game_code optional; from IPL header (avoids a second cart read)
-- @param use_color when true, dynamic parts use dark cyan (inl_ui.VALUE).
-- @return rom_size_kb, already_printed_size_line (second is true when game code matched n64-gameid data)
local function detect_rom_size_kb(game_code, use_color)
	local code = game_code or ""
	code = code:gsub("^%s+", ""):gsub("%s+$", "")
	local from_db = KNOWN_ROM_KB_BY_GAMECODE[code]
	if not from_db and #code == 3 then
		from_db = KNOWN_ROM_KB_BY_GAMECODE[code .. "E"]
	end
	if from_db then
		local mbit = from_db // 128
		local kb_disp = format_int_commas(from_db)
		local mbit_disp = format_int_commas(mbit)
		if use_color then
			io.write(inl_ui.WHITE .. "Game code " .. inl_ui.RESET .. inl_ui.VALUE .. code .. inl_ui.RESET
				.. inl_ui.WHITE .. " -> cartridge size " .. inl_ui.RESET .. inl_ui.VALUE .. kb_disp .. inl_ui.RESET
				.. inl_ui.WHITE .. " KB (" .. inl_ui.RESET .. inl_ui.VALUE .. mbit_disp .. inl_ui.RESET
				.. inl_ui.WHITE .. " Mbit)." .. inl_ui.RESET .. "\n")
			io.flush()
		else
			print(string.format(
				"Game code %s -> cartridge size %s KB (%s Mbit).",
				code,
				kb_disp,
				mbit_disp
			))
		end
		return from_db, true
	end

	if use_color then
		io.write(inl_ui.WHITE .. "Game code " .. inl_ui.RESET .. inl_ui.VALUE .. code .. inl_ui.RESET
			.. inl_ui.WHITE .. " not in known table; using mirror heuristic" .. inl_ui.RESET .. "\n")
		io.flush()
	else
		print(string.format("Game code %s not in known table; defaulting to mirror heuristic", code))
	end

	-- Moderate sample: large enough to avoid noise, small enough to reduce edge mismatches on 8/16 MiB.
	local sample = 512
	local best = nil
	for _, s_kb in ipairs(CANDIDATE_ROM_KB) do
		if mirror_period_matches(s_kb, sample) then
			if best == nil or s_kb < best then
				best = s_kb
			end
		end
	end
	if best then
		return best, false
	end

	print("No mirror boundary matched common sizes; dumping 64 MiB (" .. format_int_commas(65536) .. " KiB).")
	print("Trim the dumped file or re-run with explicit -k / -z, or add the ROM ID and KiB size to data\\n64-gameid.tsv.")
	return 65536, false
end

-- Shown after IPL header when PowerShell defers the banner (INLRETRO_PARAMS_CAPTION / _CMD).
local function print_deferred_parameters_banner(use_color)
	local cap = os.getenv("INLRETRO_PARAMS_CAPTION")
	local cmd = os.getenv("INLRETRO_PARAMS_CMD")
	if cap == nil or cap == "" or cmd == nil or cmd == "" then
		return
	end
	print("")
	if use_color then
		print(inl_ui.LABEL .. cap .. inl_ui.RESET)
		print(inl_ui.VALUE .. cmd .. inl_ui.RESET)
	else
		print(cap)
		print(cmd)
	end
	print("")
end

--dump the SNES ROM starting at the provided bank
--/ROMSEL is always low for this dump
local function dump_rom( file, rom_size_KB, debug, use_color )

	local KB_per_bank = 64 --AD0-15 = 64K address space, A0 ignored so 1Byte per address!
	local addr_base = 0x0000  -- control signals are manually controlled

	local bank_base = 0x1000  --N64 roms start at address 0x1000_0000

	local num_reads = math.floor(rom_size_KB / KB_per_bank)
	local read_count = 0
--	local read_count = 512 --second half of RE2


	--[[
	dict.n64("N64_SET_BANK", bank_base + 0)
	dict.n64("N64_LATCH_ADDR", 0x0000)
	print("read: ", help.hex(dict.n64("N64_RD")))
	print("read: ", help.hex(dict.n64("N64_RD")))
	dict.n64("N64_SET_BANK", bank_base + 0)
	dict.n64("N64_LATCH_ADDR", 0x0000)
	dump.dumptofile( file, KB_per_bank, addr_base, "N64_ROM_PAGE", false )

	dict.n64("N64_LATCH_ADDR", 0x0000)
	print("read: ", help.hex(dict.n64("N64_RD")))
	print("read: ", help.hex(dict.n64("N64_RD")))
	dict.n64("N64_LATCH_ADDR", 0x0000)
	dump.dumptofile( file, KB_per_bank, addr_base, "N64_ROM_PAGE", false )
	--]]

	while ( read_count < num_reads ) do

		if debug then print( "dump ROM part ", read_count, " of ", num_reads) end

		if (read_count % 8 == 0) then
			inl_ui.emit_rom_bank_progress(read_count, num_reads - 1)
		end

		--select desired bank
		dict.n64("N64_SET_BANK", (bank_base+read_count))

		--dump a 64KByte chunk of rom
		dump.dumptofile( file, KB_per_bank, addr_base, "N64_ROM_PAGE", false )

		--prob don't need this till done..
		dict.n64("N64_RELEASE_BUS")

		read_count = read_count + 1
	end

	dict.n64("N64_RELEASE_BUS")

end

-- Post-dump file stats: same wording as FileAnalysis.psm1-style; labels/values via inl_ui.print_kv (aligned).
local function print_post_dump_rom_analysis(rom_size_kb, path, expected_bytes, elapsed_sec, use_ansi)
	-- INL Retro Interface shows ROM analysis + timing under "Process Summary" in PowerShell.
	if os.getenv("INLRETRO_INTERFACE") == "1" then
		return
	end
	use_ansi = (use_ansi ~= false)
	local f = io.open(path, "rb")
	if not f then
		print("Could not open dumped file for analysis: " .. tostring(path))
		return
	end

	local file_size = f:seek("end")
	f:seek("set", 0)

	local sig = {}
	local zeros = 0
	local leading = 0
	local seen_nonzero = false
	local chunk_size = 65536
	while true do
		local block = f:read(chunk_size)
		if not block or #block == 0 then break end
		for i = 1, #block do
			local b = string.byte(block, i)
			if #sig < 16 then
				sig[#sig + 1] = b
			end
			if b == 0 then
				zeros = zeros + 1
				if not seen_nonzero then
					leading = leading + 1
				end
			else
				seen_nonzero = true
			end
		end
	end
	f:close()

	local non_zero = file_size - zeros
	local used_pct = file_size > 0 and round1((non_zero / file_size) * 100) or 0
	local zero_pct = file_size > 0 and round1((zeros / file_size) * 100) or 0

	local file_size_kb = math.floor(file_size / 1024 + 0.5)
	local size_tail = format_int_commas(file_size_kb) .. " KB (" .. format_int_commas(file_size) .. " bytes)"

	print("")
	if use_ansi then
		inl_ui.print_labeled_line("Game ROM file size", size_tail, true)
		inl_ui.print_labeled_line("Used space",
			format_int_commas(non_zero) .. " bytes (" .. used_pct .. "%)", true)
		inl_ui.print_labeled_line("Free space",
			format_int_commas(zeros) .. " bytes (" .. zero_pct .. "%)", true)
		if file_size >= 16 then
			local hex = {}
			for i = 1, #sig do
				hex[i] = string.format("%02X", sig[i])
			end
			inl_ui.print_labeled_line("File Signature", table.concat(hex, " "), true)
		end
	else
		print("Game ROM file size: " .. size_tail)
		print("Used space: " .. format_int_commas(non_zero) .. " bytes (" .. used_pct .. "%)")
		print("Free space: " .. format_int_commas(zeros) .. " bytes (" .. zero_pct .. "%)")
		if file_size >= 16 then
			local hex = {}
			for i = 1, #sig do
				hex[i] = string.format("%02X", sig[i])
			end
			print("File Signature: " .. table.concat(hex, " "))
		end
	end

	if expected_bytes and file_size ~= expected_bytes then
		local msg = "Expected dump size " .. format_int_commas(expected_bytes)
			.. " bytes but file is " .. format_int_commas(file_size) .. " bytes."
		if use_ansi then
			io.write(inl_ui.DARK_YELLOW .. msg .. inl_ui.RESET .. "\n")
			io.flush()
		else
			print(msg)
		end
	end

	if file_size > 0 and leading > 0 then
		if use_ansi then
			io.write("\n")
			io.write(inl_ui.DARK_YELLOW .. "Leading padding detected: " .. leading
				.. " bytes of zeros at start of file." .. inl_ui.RESET .. "\n")
			io.write(inl_ui.DARK_YELLOW .. "First non-zero byte at offset " .. leading
				.. " / 0x" .. help.hex(leading) .. "." .. inl_ui.RESET .. "\n")
			io.write(inl_ui.DARK_YELLOW .. "Note: This padding may be intentional for certain cartridge boards." .. inl_ui.RESET .. "\n")
			io.flush()
		else
			print("")
			print("Leading padding detected: " .. leading .. " bytes of zeros at start of file.")
			print("First non-zero byte at offset " .. leading .. " / 0x" .. help.hex(leading) .. ".")
			print("Note: This padding may be intentional for certain cartridge boards.")
		end
	end

	-- Timing: same label/value colors as File ROM stats (two lines).
	if elapsed_sec and elapsed_sec > 0 then
		local kbps = rom_size_kb / elapsed_sec
		local time_str = format_total_time_sec(elapsed_sec) or ""
		inl_ui.print_kv("Total time", time_str, use_ansi)
		inl_ui.print_kv("Average speed", string.format("%.2f", kbps) .. " KBps", use_ansi)
	end
end

-- Big-endian cartridge order matches the usual .z64 convention; prefer that extension on disk.
local function prefer_z64_dump_path(path)
	if path == nil or path == "" then
		return path
	end
	local pl = path:lower()
	if pl:sub(-4) == ".n64" then
		return path:sub(1, -5) .. ".z64"
	end
	return path
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
	local z64_rename_from = nil
	if read and dumpfile ~= nil and dumpfile ~= "" then
		local zpath = prefer_z64_dump_path(dumpfile)
		if zpath ~= dumpfile then
			z64_rename_from = dumpfile
			process_opts["dump_filename"] = zpath
			dumpfile = zpath
		end
	end
	local flashfile = process_opts["flash_filename"]
	local verifyfile = process_opts["verify_filename"]
	local dumpram = process_opts["dumpram"]
	local dumpram_filename = process_opts["dumpram_filename"]
	local writeram = process_opts["writeram"]
	local writeram_filename = process_opts["writeram_filename"]

	local use_color = inl_ui.use_ansi()

	local rv = nil
	local file 
	local rom_size = console_opts["rom_size_kbyte"]
	local wram_size = console_opts["wram_size_kb"]
	local mirror = console_opts["mirror"]


--initialize device i/o for N64
	dict.io("IO_RESET")
	dict.io("N64_INIT")

	local n64_hdr = read_n64_ipl_header()

	if test then
		print("")
		if use_color then
			print(inl_ui.WHITE .. "Nintendo 64 Cartridge Header:" .. inl_ui.RESET)
		else
			print("Nintendo 64 Cartridge Header:")
		end
		print_n64_header(n64_hdr, use_color)
		print_deferred_parameters_banner(use_color)
	end

	if read and z64_rename_from then
		if use_color then
			io.write(inl_ui.WHITE .. "\nINL Retro Dumper uses .z64 for big-endian dump (adjusted from: "
				.. inl_ui.RESET .. inl_ui.VALUE .. z64_rename_from .. inl_ui.RESET
				.. inl_ui.WHITE .. ")" .. inl_ui.RESET .. "\n")
			io.flush()
		else
			print("\nINL Retro Dumper uses .z64 for big-endian dump (adjusted from: " .. z64_rename_from .. ")")
		end
	end

	if (read or verify) and (rom_size == nil or rom_size == 0) then
		if use_color then
			io.write(inl_ui.WHITE .. "Cartridge ROM size is gathered from internal source " .. inl_ui.RESET
				.. inl_ui.VALUE .. "data\\n64-gameid.tsv" .. inl_ui.RESET .. ".\n")
			io.flush()
		else
			print("Cartridge ROM size is gathered from internal source data\\n64-gameid.tsv.")
		end
		local rom_size_known_printed
		rom_size, rom_size_known_printed = detect_rom_size_kb(n64_hdr.game_code, use_color)
		console_opts["rom_size_kbyte"] = rom_size
		if not rom_size_known_printed then
			local mbit = rom_size // 128
			local rom_kb_disp = format_int_commas(rom_size)
			local mbit_disp = format_int_commas(mbit)
			if use_color then
				io.write(inl_ui.WHITE .. "Using cartridge size" .. inl_ui.RESET .. inl_ui.VALUE .. rom_kb_disp .. inl_ui.RESET
					.. inl_ui.WHITE .. "  KB (" .. inl_ui.RESET .. inl_ui.VALUE .. mbit_disp .. inl_ui.RESET
					.. inl_ui.WHITE .. "  Mbit)" .. inl_ui.RESET .. "\n")
				io.flush()
			else
				print(string.format("Using cartridge size %s KB (%s Mbit)", rom_kb_disp, mbit_disp))
			end
		end
	elseif (read or verify) and rom_size and rom_size > 0 then
		local mbit = rom_size // 128
		local rom_kb_disp = format_int_commas(rom_size)
		local mbit_disp = format_int_commas(mbit)
		if use_color then
			io.write(inl_ui.WHITE .. "Cartridge size from command line:" .. inl_ui.RESET
				.. inl_ui.VALUE .. rom_kb_disp .. inl_ui.RESET
				.. inl_ui.WHITE .. " KB (" .. inl_ui.RESET .. inl_ui.VALUE .. mbit_disp .. inl_ui.RESET
				.. inl_ui.WHITE .. " Mbit)" .. inl_ui.RESET .. "\n")
			io.flush()
		else
			print(string.format("Cartridge size from command line: %s KB (%s Mbit)", rom_kb_disp, mbit_disp))
		end
	end


-- Save data (EEPROM / SRAM / Flash) is not on the mask-ROM bus this dumper uses.
-- Firmware only implements N64 ROM reads (shared_dict_n64.h / n64.c); there is no
-- joybus/EEPROM bit-bang path in-tree. -a / -b are accepted but cannot dump or write saves yet.
	if dumpram then
		print("")
		local dumpram_lines = {
			"---[ Important ]---",
			"Unlike NES and SNES cartridges, which typically store save data in battery-backed SRAM that can be dumped directly ",
			"alongside the ROM. Nintendo 64 cartridges use a variety of save types (EEPROM, SRAM, or Flash RAM) that require ",
			"different handling and are not supported by the current hardware."	
		}
		for _, line in ipairs(dumpram_lines) do
			if use_color then
				io.write(inl_ui.YELLOW .. line .. inl_ui.RESET .. "\n")
			else
				print(line)
			end
		end
		if use_color then
			io.write(inl_ui.YELLOW .. inl_ui.align_label("Requested output was") .. inl_ui.RESET
				.. inl_ui.VALUE .. tostring(dumpram_filename or "") .. inl_ui.RESET .. "\n")
			io.flush()
		else
			print(inl_ui.align_label("Requested output was") .. tostring(dumpram_filename or ""))
		end
	end

--dump the cart to dumpfile (format / size / output path under Parameters used in PowerShell; banner only here)
	if read then
		if rom_size == nil or rom_size <= 0 then
			error("Invalid ROM size after detection (need -k > 0 or working auto-detect)")
		end

		file = assert(io.open(dumpfile, "wb"))

		print("")
		if use_color then
			print(inl_ui.WHITE .. "Dumping Nintendo 64 Cartridge:" .. inl_ui.RESET)
		else
			print("Dumping Nintendo 64 Cartridge:")
		end
		local dump_t0 = os.clock()
		dump_rom(file, rom_size, false, use_color)
		assert(file:close())
		local dump_elapsed = os.clock() - dump_t0

		print("Finished dumping the Nintendo 64 Cartridge.")
		print_post_dump_rom_analysis(rom_size, dumpfile, rom_size * 1024, dump_elapsed, inl_ui.use_ansi())
	end

--erase the cart
	if erase then

	--	erase_flash()
	end

	if writeram then
		print("")
		local writeram_lines = {
			"Save write (-b) is not supported with the current hardware/firmware.",
			"Unlike NES and SNES cartridges, which typically store save data in battery-backed SRAM that can be dumped directly ",
			"alongside the ROM. Nintendo 64 cartridges use a variety of save types (EEPROM, SRAM, or Flash RAM) that require ",
			"different handling and are not supported by the current hardware.",
		}
		for _, line in ipairs(writeram_lines) do
			if use_color then
				io.write(inl_ui.YELLOW .. line .. inl_ui.RESET .. "\n")
			else
				print(line)
			end
		end
		if use_color then
			io.write(inl_ui.YELLOW .. inl_ui.align_label("Requested input was") .. inl_ui.RESET
				.. inl_ui.VALUE .. tostring(writeram_filename or "") .. inl_ui.RESET .. "\n")
			io.flush()
		else
			print(inl_ui.align_label("Requested input was") .. tostring(writeram_filename or ""))
		end
	end


--program flashfile to the cart
	if program then

--		--open file
--		file = assert(io.open(flashfile, "rb"))
--		--determine if auto-doubling, deinterleaving, etc, 
--		--needs done to make board compatible with rom
--
--		--flash cart
--		flash_rom(file, rom_size, snes_mapping, true)
--
--		--close file
--		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
--		print("\nPost dumping SNES ROM...")
--		--for now let's just dump the file and verify manually
--
--		file = assert(io.open(verifyfile, "wb"))
--
--		--dump cart into file
--		dump_rom(file, rom_size, false)
--
--		--close file
--		assert(file:close())
--		print("DONE Post dumping SNES ROM")
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
n64.process = process

-- return the module's table
return n64
