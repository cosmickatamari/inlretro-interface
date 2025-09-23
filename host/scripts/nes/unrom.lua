-- UNROM (UxROM / mapper 2) dumper — optimized for DuckTales and similar games
-- Focus: robust PRG dumping with proper bank switching and header generation
-- Requires: scripts.app.dict, scripts.app.nes, scripts.app.dump, scripts.app.buffers

-- ==== Portable bitwise AND shim (Lua 5.1/5.2/5.3/LuaJIT) ====
local BAND
if _G.bit32 and bit32.band then
  BAND = bit32.band          -- Lua 5.2+
elseif _G.bit and bit.band then
  BAND = bit.band            -- LuaJIT / LuaBitOp
else
  -- Pure-Lua fallback
  BAND = function(a, b)
    local r, bitv = 0, 1
    if a < 0 then a = 0 end
    if b < 0 then b = 0 end
    while a > 0 or b > 0 do
      local abit = a % 2
      local bbit = b % 2
      if abit == 1 and bbit == 1 then r = r + bitv end
      a = (a - abit) / 2
      b = (b - bbit) / 2
      bitv = bitv * 2
    end
    return r
  end
end
-- ==== End shim ====

-- Module table
local unrom = {}

-- Imports
local dict    = require "scripts.app.dict"
local nes     = require "scripts.app.nes"
local dump    = require "scripts.app.dump"
local buffers = require "scripts.app.buffers"

-- Mapper name (try both)
local mapname = (buffers.op_buffer and buffers.op_buffer["UNROM"]) and "UNROM" or "UxROM"

-- State
local banktable_base = nil          -- address of contiguous 00..n-1 table in fixed PRG, if present
local bankaddr_lookup = nil         -- per-value safe write addresses for bus-conflict-safe select

-- Header writer - fixed for UNROM (mapper 2)
local function create_header(file, prgKB, chrKB)
  local mirroring = nes.detect_mapper_mirroring()
  local opb = buffers.op_buffer and buffers.op_buffer[mapname] or 0
  
  -- Force UNROM mapper (2) and proper flags
  local flags6 = 0x02  -- Mapper 2 (UNROM)
  local flags7 = 0x00  -- No special features
  
  -- Write NES header
  file:write(string.char(0x4E, 0x45, 0x53, 0x1A))  -- "NES" + delimiter
  file:write(string.char(prgKB / 16))              -- PRG-ROM size in 16KB units
  file:write(string.char(chrKB / 8))               -- CHR-ROM size in 8KB units (0 for CHR-RAM)
  file:write(string.char(flags6))                  -- Flags 6
  file:write(string.char(flags7))                  -- Flags 7
  file:write(string.char(0x00, 0x00, 0x00, 0x00))  -- Flags 8-11
  file:write(string.char(0x00, 0x00, 0x00, 0x00))  -- Flags 12-15
end

-- Find a contiguous 00..(bank_count-1) table in the fixed bank ($C000-$FFFF).
local function find_banktable(bank_count)
  local search_base = 0x0C   -- $C000
  local KB_search   = 16

  local buf = ""
  local function sink(data) buf = buf .. data end
  dump.dumptocallback(sink, KB_search, search_base, "NESCPU_4KB", false)

  local bytes = { buf:byte(1, #buf) }
  local needed = bank_count
  for pos = 1, (#bytes - needed + 1) do
    local ok = true
    for v = 0, needed - 1 do
      if bytes[pos + v] ~= v then ok = false; break end
    end
    if ok then
      return 0xC000 + (pos - 1)
    end
  end
  return nil
end

-- Build per-value safe write addresses (bus-conflict-safe): choose any byte b where (b & v) == v.
local function build_bankaddr_lookup(bank_count)
  local search_base = 0x0C   -- $C000
  local KB_search   = 16

  local buf = ""
  local function sink(data) buf = buf .. data end
  dump.dumptocallback(sink, KB_search, search_base, "NESCPU_4KB", false)

  local bytes = { buf:byte(1, #buf) }
  local addrs = {}

  for v = 0, bank_count - 1 do
    if v == 0 then
      addrs[v] = 0xC000  -- any address works for 0
    else
      local found
      for i = 1, #bytes do
        if BAND(bytes[i], v) == v then
          found = 0xC000 + i - 1
          break
        end
      end
      if not found then
        return nil
      end
      addrs[v] = found
    end
  end

  return addrs
end

-- PRG dump for UNROM (mapper 2) - optimized for DuckTales
local function dump_prgrom(file, prgKB, debug)
  local KB_per_read = 16
  local num_reads   = prgKB / KB_per_read
  local addr_8000   = 0x08   -- $8000
  local addr_C000   = 0x0C   -- $C000

  -- Determine bank select method
  local bank_count = num_reads - 1
  if not banktable_base then
    banktable_base = find_banktable(bank_count)
    if banktable_base then
      print(("Found banktable at address $%X"):format(banktable_base))
    else
      print("Banktable not found; using per-value lookup")
      bankaddr_lookup = bankaddr_lookup or build_bankaddr_lookup(bank_count)
      if not bankaddr_lookup then 
        print("Warning: couldn't build per-value lookup, using direct writes")
        -- Fallback: use direct writes to $8000-$FFFF
        bankaddr_lookup = {}
        for v = 0, bank_count - 1 do
          bankaddr_lookup[v] = 0x8000 + v  -- Direct write to switchable area
        end
      end
    end
  end

  -- Switchable banks ($8000-$BFFF)
  for bank = 0, bank_count - 1 do
    if debug then print("Dumping PRG bank", bank, "of", bank_count - 1) end
    
    -- Select bank
    if banktable_base then
      dict.nes("NES_CPU_WR", banktable_base + bank, bank)
    else
      local sel_addr = bankaddr_lookup[bank]
      if not sel_addr then 
        -- Fallback: write bank number to $8000 + bank
        sel_addr = 0x8000 + bank
      end
      dict.nes("NES_CPU_WR", sel_addr, bank)
    end
    
    -- Bank switch completed
    
    -- Dump the bank
    print("File position before bank", bank, ":", file:seek())
    dump.dumptofile(file, KB_per_read, addr_8000, "NESCPU_4KB", false)
    print("File position after bank", bank, ":", file:seek())
    file:flush()  -- Force flush to disk
  end

  -- Fixed bank ($C000-$FFFF)
  if debug then print("Dumping PRG fixed bank at $C000") end
  print("File position before fixed bank:", file:seek())
  dump.dumptofile(file, KB_per_read, addr_C000, "NESCPU_4KB", false)
  print("File position after fixed bank:", file:seek())
  file:flush()  -- Force flush to disk
end

-- Top-level entry
local function process(process_opts, console_opts)
  local test       = process_opts["test"]
  local read       = process_opts["read"]
  local erase      = process_opts["erase"]
  local program    = process_opts["program"]
  local verify     = process_opts["verify"]
  local dumpfile   = process_opts["dump_filename"]

  local prg_size   = console_opts["prg_rom_size_kb"] or 0
  local chr_size   = console_opts["chr_rom_size_kb"] or 0

  if test then
    print("UNROM: test mode detected — continuing (no-op) so read can proceed")
  end

  if (not read) and (not erase) and (not program) and (not verify) then
    print("UNROM: nothing to do (no read/erase/program/verify flags).")
    dict.io("IO_RESET")
    return
  end

  if prg_size <= 0 then
    error("UNROM: prg_rom_size_kb is 0/undefined; pass -x <size in KB> (e.g., -x 128)")
  end

  -- Force CHR size to 0 for UNROM (uses CHR-RAM)
  if chr_size > 0 then
    print("UNROM: Forcing CHR size to 0 (UNROM uses CHR-RAM)")
    chr_size = 0
  end

  if read then
    print("UNROM: Starting PRG-ROM dump...")
    print("PRG size:", prg_size, "KB")
    print("CHR size:", chr_size, "KB (CHR-RAM)")
    
    local f = assert(io.open(dumpfile, "wb"))
    create_header(f, prg_size, chr_size)
    print("Header written, file position:", f:seek())
    dump_prgrom(f, prg_size, true)  -- Enable debug output
    print("Final file position before close:", f:seek())
    assert(f:close())
    print("DONE dumping PRG-ROM")
  end

  dict.io("IO_RESET")
end

-- Exports
unrom.process = process
return unrom