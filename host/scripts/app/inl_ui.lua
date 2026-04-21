--[[
  Shared terminal UI for inlretro Lua scripts: ANSI SGR codes, aligned label/value
  lines (INL interface / PowerShell-friendly), and when to emit color.

  Require: local inl_ui = require "scripts.app.inl_ui"

  Console scripts supply their own header fields and messages; this module only
  centralizes styling helpers so NES/SNES/N64/etc. can share one scheme.
--]]

local M = {}

-- Default label column: "Label:" padded to this width before value (matches host Write-AlignedSummaryLine).
M.VALUE_COLUMN = 30

-- SGR: bright cyan labels, dark cyan values, white prose, yellow notices (same as legacy n64/basic.lua).
M.LABEL = "\27[96m"
M.VALUE = "\27[36m"
M.WHITE = "\27[37m"
M.DARK_YELLOW = "\27[33m"
M.YELLOW = "\27[33m"
M.RESET = "\27[0m"

function M.align_label(label, width)
	label = tostring(label or "")
	width = width or M.VALUE_COLUMN
	local prefix = label .. ":"
	if #prefix >= width then
		return prefix .. " "
	end
	return prefix .. string.rep(" ", width - #prefix)
end

function M.print_kv(label, value, use_color)
	label = tostring(label or "")
	value = tostring(value or "")
	if use_color then
		io.write(M.LABEL .. M.align_label(label) .. M.RESET .. M.VALUE .. value .. M.RESET .. "\n")
		io.flush()
	else
		print(M.align_label(label) .. value)
	end
end

-- Same alignment as print_kv; label unstyled, value uses VALUE color (see emit_rom_bank_progress for INL interface).
function M.print_kv_white_label(label, value, use_color)
	label = tostring(label or "")
	value = tostring(value or "")
	if use_color then
		io.write(M.align_label(label) .. M.VALUE .. value .. M.RESET .. "\n")
		io.flush()
	else
		print(M.align_label(label) .. value)
	end
end

-- Under INLRETRO_INTERFACE=1 (Invoke-INLRetro), emit a machine-readable row so PowerShell can
-- color the label with VT 97 without parsing English text or Write-Host palette mapping.
function M.emit_rom_bank_progress(read_count, num_reads_minus_one)
	read_count = tonumber(read_count) or 0
	num_reads_minus_one = tonumber(num_reads_minus_one) or 0
	if os.getenv("INLRETRO_INTERFACE") == "1" then
		io.write(string.format("INL-ROM-BANK\t%d\t%d\n", read_count, num_reads_minus_one))
		io.flush()
		return
	end
	M.print_kv_white_label("Dumping ROM bank",
		string.format("%d of %d", read_count, num_reads_minus_one),
		M.use_ansi())
end

function M.print_labeled_line(label, value, use_color)
	M.print_kv(label, value, use_color)
end

--[[
  True when scripts should emit ANSI escapes: direct VT console, Windows Terminal,
  INLRETRO_FORCE_ANSI=1 (PowerShell pipe), or non-Windows; false on Windows conhost
  without VT unless TERM/WT_SESSION says otherwise.

  NO_COLOR always wins. For in-script opt-in after startup, see force_ansi().
--]]
function M.use_ansi()
	if os.getenv("NO_COLOR") then
		return false
	end
	if os.getenv("INLRETRO_FORCE_ANSI") == "1" then
		return true
	end
	local vt = rawget(_G, "inlretro_vt_ansi")
	if vt == true then
		return true
	end
	if package.config:sub(1, 1) ~= "\\" then
		return true
	end
	if vt == false then
		local term = os.getenv("TERM")
		if term and term ~= "dumb" then
			return true
		end
		if os.getenv("WT_SESSION") then
			return true
		end
		return false
	end
	local term = os.getenv("TERM")
	if term and term ~= "dumb" then
		return true
	end
	if os.getenv("WT_SESSION") then
		return true
	end
	return false
end

--[[
  Opt in to emitting ANSI from Lua after the process has started (sets global inlretro_vt_ansi).
  Does not override NO_COLOR. Prefer INLRETRO_FORCE_ANSI=1 from the shell when possible.
--]]
function M.force_ansi()
	rawset(_G, "inlretro_vt_ansi", true)
end

-- Tab-concatenate arguments like Lua's print().
function M.concat_print_tab(...)
	local n = select("#", ...)
	if n == 0 then
		return ""
	end
	local t = {}
	for i = 1, n do
		t[i] = tostring(select(i, ...))
	end
	return table.concat(t, "\t")
end

local function is_debug_passthrough(msg)
	return msg:match("^DEBUG:") or msg:match("^%s*DEBUG:") or msg:match("^%s*DEBUG%s")
end

--[[
  Run fn with global print() routed through INL styling when use_ansi() is true:
  normal lines = white prose; WARNING / ERROR!! / ERROR: = yellow; DEBUG: = unstyled (passthrough).
  Used from inlretro2 main() for most consoles so mapper scripts share output styling without
  editing every print() call site.

  Call sites may skip this wrapper for a specific console (e.g. N64) when global print must not
  be overridden—see inlretro2.lua. That is a deliberate dispatch choice, not a defect in this
  function: the hook always restores the previous print when fn() returns or errors.
--]]
function M.with_styled_print(fn)
	if not M.use_ansi() then
		return fn()
	end
	local orig = print
	print = function(...)
		local msg = M.concat_print_tab(...)
		if is_debug_passthrough(msg) then
			orig(...)
			return
		end
		if msg:find("WARNING", 1, true) or msg:find("ERROR!!", 1, true) or msg:find("ERROR:", 1, true)
			or msg:find("CHECKSUM MISMATCH", 1, true) or msg:find("BAD DUMP", 1, true)
			or msg:find("UNSUPPORTED MAPPER", 1, true) or msg:find("UNSUPPORTED OPERATION", 1, true) then
			io.write(M.YELLOW .. msg .. M.RESET .. "\n")
			io.flush()
			return
		end
		io.write(M.WHITE .. msg .. M.RESET .. "\n")
		io.flush()
	end
	local ok, err = pcall(fn)
	print = orig
	if not ok then
		error(err)
	end
end

return M
