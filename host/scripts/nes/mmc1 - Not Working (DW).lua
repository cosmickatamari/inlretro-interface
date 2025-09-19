-- scripts/nes/mmc1.lua
-- MMC1 dumper with conservative timing and Dragon Warrior–safe 64KB PRG path.
-- Keeps original INL flow; adds robust 32KB triple-read + RESET-vector ordering for PRG=64KB.

-- ========= Module =========
local mmc1 = {}

-- ========= Imports =========
local dict    = require "scripts.app.dict"
local nes     = require "scripts.app.nes"
local dump    = require "scripts.app.dump"
local flash   = require "scripts.app.flash"
local buffers = require "scripts.app.buffers"
local help    = require "scripts.app.help"

-- ========= Tiny sleep helper =========
local function usleep(us)
  if help and help.usleep then help.usleep(us)
  elseif help and help.sleep_ms then help.sleep_ms(math.max(1, math.floor((us + 999) / 1000))) end
end

-- ==== Bit-banged MMC1 write (reset + 5 LSB->MSB CPU writes) ====
local function mmc1_write(addr, value)
  -- reset the shift register (D7=1 to any MMC1 reg)
  dict.nes("NES_CPU_WR", 0x8000, 0x80)
  usleep(4000)
  -- shift in 5 bits, LSB first, with pacing
  for i = 0, 4 do
    local bit = math.floor(value / (2^i)) % 2
    dict.nes("NES_CPU_WR", addr, bit)
    _ = dict.nes("NES_CPU_RD", 0x8000); _ = dict.nes("NES_CPU_RD", 0xC000)
    usleep(3000)   -- if still flaky, try 3000
  end
  usleep(20000)    -- if still flaky, try 20000
end

local function set_mode0() mmc1_write(0x8000, 0x08) end  -- 32KB PRG @ $8000
local function set_mode2() mmc1_write(0x8000, 0x0C) end  -- 16KB switch @ $C000
local function set_mode3() mmc1_write(0x8000, 0x0E) end  -- 16KB switch @ $8000
local function set_prg_bank(b) mmc1_write(0xE000, (b % 16)) end



-- ========= Tunables =========
local READ_RETRIES = READ_RETRIES or 6   -- safe default if not already set elsewhere

-- ========= File constants =========
local mapname = "MMC1"

-- ========= Header =========
local function create_header(file, prgKB, chrKB)
  local prg_units = math.floor((tonumber(prgKB) or 0) / 16)
  local chr_units = math.floor((tonumber(chrKB) or 0) / 8)
  local flags6 = 0x10 + 0x02 + 0x01  -- MMC1 + battery + vertical
  local hdr = {
    0x4E,0x45,0x53,0x1A,
    prg_units & 0xFF, chr_units & 0xFF,
    flags6 & 0xFF, 0x00,     -- flags7
    0x01, 0x00, 0x00, 0x00,  -- PRG-RAM = 1 (8KB)
    0x00, 0x00, 0x00, 0x00
  }
  file:write(string.char(table.unpack(hdr)))
end

local function init_mapper(debug)
  _ = dict.nes("NES_CPU_RD", 0x8000)
  dict.nes("NES_CPU_WR", 0x8000, 0x80) -- reset shift
  set_mode0()                          -- 32KB PRG
  mmc1_write(0xE000, 0x10)             -- PRG=0 + WRAM disable (bit4=1)
  -- benign CHR state
  mmc1_write(0xA000, 0x12)
  mmc1_write(0xC000, 0x15)
end

-- ========= Mirroring self-test (unchanged) =========
local function mirror_test(debug)
  init_mapper()

  mmc1_write(0x8000, 0x00)
  if nes.detect_mapper_mirroring() ~= "1SCNA" then print("MMC1 mirror test fail (1 screen A)") return false end

  mmc1_write(0x8000, 0x01)
  if nes.detect_mapper_mirroring() ~= "1SCNB" then print("MMC1 mirror test fail (1 screen B)") return false end

  mmc1_write(0x8000, 0x02)
  if nes.detect_mapper_mirroring() ~= "VERT" then print("MMC1 mirror test fail (Vertical)") return false end

  mmc1_write(0x8000, 0x03)
  if nes.detect_mapper_mirroring() ~= "HORZ" then print("MMC1 mirror test fail (Horizontal)") return false end

  if debug then print("MMC1 mirror test passed") end
  return true
end

-- ========= Optional ID probes (unchanged) =========
local function prgrom_manf_id(debug)
  init_mapper()
  if debug then print("reading PRG-ROM manf ID") end
  dict.nes("NES_CPU_WR", 0xD555, 0xAA)
  dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
  dict.nes("NES_CPU_WR", 0xD555, 0x90)
  local rv = dict.nes("NES_CPU_RD", 0x8000); if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end
  rv = dict.nes("NES_CPU_RD", 0x8001);      if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end
  dict.nes("NES_CPU_WR", 0x8000, 0xF0)
end

local function chrrom_manf_id(debug)
  init_mapper()
  if debug then print("reading CHR-ROM manf ID") end
  dict.nes("NES_PPU_WR", 0x1555, 0xAA)
  dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
  dict.nes("NES_PPU_WR", 0x1555, 0x90)
  local rv = dict.nes("NES_PPU_RD", 0x0000); if debug then print("attempted read CHR-ROM manf ID:", string.format("%X", rv)) end
  rv = dict.nes("NES_PPU_RD", 0x0001);      if debug then print("attempted read CHR-ROM prod ID:", string.format("%X", rv)) end
  dict.nes("NES_PPU_WR", 0x8000, 0xF0)
end

-- ========= PRG dump =========
local function dump_prgrom(file, rom_size_KB, debug)
  -- helper: write control multiple times (stickier on finicky boards)
  
	local function mmc1_ctrl(val)
	  mmc1_write(0x8000, val)
	end


  -- quick open-bus probe at a CPU address
  local function looks_open_bus_at(addr)
    local b0 = dict.nes("NES_CPU_RD", addr)
    for i = 1, 64 do
      if dict.nes("NES_CPU_RD", addr + (i % 16)) ~= b0 then return false end
    end
    return true
  end

  -- ===== 64KB (Dragon Warrior etc.): robust 32KB-first path =====
  if rom_size_KB == 64 then
    if debug then print("PRG 64KB: majority-read 32KB windows (mode0)") end

    local function looks_open_bus(buf, sample_len)
      if type(buf) ~= "string" then return true end
      local n = sample_len or 1024
      if #buf < n then return true end
      local b0 = string.byte(buf, 1)
      for i = 2, n do if string.byte(buf, i) ~= b0 then return false end end
      return true
    end

    local function read_32k_once(reg)
      init_mapper()
      mmc1_ctrl(0x08)                       -- control=mode0 (32KB PRG)
	mmc1_write(0xE000, reg)
      usleep(8000)
      local lo, hi = {}, {}
      for i = 0, (16*1024)-1 do
        lo[#lo+1] = string.char(dict.nes("NES_CPU_RD", 0x8000 + i))
        hi[#hi+1] = string.char(dict.nes("NES_CPU_RD", 0xC000 + i))
      end
      return table.concat(lo) .. table.concat(hi)
    end

    local function read_32k_verified(reg)
      local attempt, max_tries = 1, READ_RETRIES
      while attempt <= max_tries do
        local a, b, c = read_32k_once(reg), read_32k_once(reg), read_32k_once(reg)
        if a and b and c then
          local all_open = looks_open_bus(a) and looks_open_bus(b) and looks_open_bus(c)
          if not all_open then
            if a == b or a == c then return a end
            if b == c then return b end
            local n = #a
            if #b == n and #c == n then
              local out = {}
              for i = 1, n do
                local A, B, C = string.byte(a,i), string.byte(b,i), string.byte(c,i)
                local maj = (A == B or A == C) and A or (B == C and B or A)
                out[i] = string.char(maj)
              end
              local m = table.concat(out)
              if not looks_open_bus(m) then return m end
            end
          end
        end
        if debug then print(string.format("PRG32 reg=%d: unstable/open (attempt %d/%d)", reg, attempt, max_tries)) end
        usleep(20000)
        attempt = attempt + 1
      end
      return nil
    end

    local win0 = read_32k_verified(0x00)
    local win1 = read_32k_verified(0x02)
    if not win0 or not win1 then error("MMC1 PRG64: failed to capture stable 32KB windows") end

    local function reset_from_last16(win32)
      if type(win32) ~= "string" or #win32 < 32*1024 then return nil end
      local last16 = win32:sub(16*1024+1, 32*1024)
      local lo = string.byte(last16, 0x3FFC - 0x4000 + 1)
      local hi = string.byte(last16, 0x3FFD - 0x4000 + 1)
      if not lo or not hi then return nil end
      return hi*256 + lo
    end
    local function valid_reset(r) return (type(r) == "number") and r >= 0x8000 and r <= 0xFFFF end

    local r01 = reset_from_last16(win1) -- last bank would live in win1 (order win0+win1)
    local r10 = reset_from_last16(win0) -- last bank would live in win0 (order win1+win0)

    if valid_reset(r01) and (not valid_reset(r10) or r01 >= r10) then
      if debug then print(string.format("PRG64: using order w0+w1 (RESET=$%04X)", r01)) end
      file:write(win0); file:write(win1)
    else
      if debug then print(string.format("PRG64: using order w1+w0 (RESET=$%04X)", r10 or 0)) end
      file:write(win1); file:write(win0)
    end
    return
  end

  -- ===== Generic path: 32KB-at-a-time (original style) =====
  local KB_per_read = 32
  local num_reads   = rom_size_KB / KB_per_read
  local read_count  = 0
  local addr_base   = 0x08  -- $8000

  while read_count < num_reads do
    if debug then print("dump PRG part ", read_count, " of ", num_reads) end
    mmc1_ctrl(0x08) -- 32KB mode
    local reg = (read_count * 2) -- LSB ignored in 32KB mode
    dict.nes("NES_MMC1_WR", 0xE000, reg)
    dict.nes("NES_MMC1_WR", 0xE000, reg)
    dict.nes("NES_MMC1_WR", 0xE000, reg)

    if looks_open_bus_at(0x8000) and looks_open_bus_at(0xC000) then
      init_mapper(); mmc1_ctrl(0x08); dict.nes("NES_MMC1_WR", 0xE000, reg)
      if looks_open_bus_at(0x8000) and looks_open_bus_at(0xC000) then
        error("MMC1 PRG: open bus detected while dumping 32KB window "..read_count)
      end
    end

    dump.dumptofile(file, KB_per_read, addr_base, "NESCPU_4KB", false)
    read_count = read_count + 1
  end
end

-- ========= CHR dump (simple/unchanged) =========
local function dump_chrrom(file, rom_size_KB, debug)
  local total = (tonumber(rom_size_KB) or 0) * 1024
  if total <= 0 then return end
  for i = 0, total-1 do
    file:write(string.char(dict.nes("NES_PPU_RD", i)))
  end
end

-- ========= (Optional) single-byte flash helpers (left intact) =========
local function wr_prg_flash_byte(addr, value, bank, debug)
  if (addr < 0x8000 or addr > 0xFFFF) then
    print("\n  ERROR! flash write to PRG-ROM", string.format("$%X", addr), "must be $8000-FFFF \n\n")
    return
  end
  dict.nes("NES_MMC1_WR", 0xC000, 0x05)
  dict.nes("NES_CPU_WR", 0xD555, 0xAA)
  dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
  dict.nes("NES_CPU_WR", 0xD555, 0xA0)
  dict.nes("NES_CPU_WR", addr, value)
  local rv, i = dict.nes("NES_CPU_RD", addr), 0
  while rv ~= value do rv = dict.nes("NES_CPU_RD", addr); i = i + 1 end
  if debug then print(i, "naks, done writing byte.") end
end

local function wr_chr_flash_byte(addr, value, bank, debug)
  if (addr < 0x0000 or addr > 0x0FFF) then
    print("\n  ERROR! flash write to CHR-ROM", string.format("$%X", addr), "must be $0000-0FFF \n\n")
    return
  end
  dict.nes("NES_MMC1_WR", 0xA000, 0x02)
  dict.nes("NES_PPU_WR", 0x1555, 0xAA)
  dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
  dict.nes("NES_PPU_WR", 0x1555, 0xA0)
  dict.nes("NES_MMC1_WR", 0xA000, bank)
  dict.nes("NES_PPU_WR", addr, value)
  local rv, i = dict.nes("NES_PPU_RD", addr), 0
  while rv ~= value do rv = dict.nes("NES_PPU_RD", addr); i = i + 1 end
  if debug then print(i, "naks, done writing byte.") end
end

-- ========= High-level flash (unchanged) =========
local function flash_prgrom(file, rom_size_KB, debug)
  init_mapper()
  print("\nProgramming PRG-ROM flash")
  local base_addr = 0x8000
  local bank_size = 32*1024
  local cur_bank  = 0
  local total_banks = rom_size_KB*1024/bank_size
  while cur_bank < total_banks do
    if (cur_bank % 2 == 0) then print("writting PRG bank: ", cur_bank, " of ", total_banks-1) end
    mmc1_write(0xE000, cur_bank<<1)
    flash.write_file(file, bank_size/1024, mapname, "PRGROM", false)
    cur_bank = cur_bank + 1
  end
  print("Done Programming PRG-ROM flash")
end

local function flash_chrrom(file, rom_size_KB, debug)
  init_mapper()
  print("\nProgramming CHR-ROM flash")
  local bank_size = 4*1024
  local cur_bank  = 0
  local total_banks = rom_size_KB*1024/bank_size
  while cur_bank < total_banks do
    if (cur_bank % 8 == 0) then print("writting CHR bank: ", cur_bank, " of ", total_banks-1) end
    dict.nes("SET_CUR_BANK", cur_bank)
    flash.write_file(file, bank_size/1024, mapname, "CHRROM", false)
    cur_bank = cur_bank + 1
  end
  print("Done Programming CHR-ROM flash")
end

-- ========= Main process =========
local function process(process_opts, console_opts)
  local test        = process_opts["test"]
  local read        = process_opts["read"]
  local erase       = process_opts["erase"]
  local program     = process_opts["program"]
  local verify      = process_opts["verify"]
  local dumpfile    = process_opts["dump_filename"]
  local flashfile   = process_opts["flash_filename"]
  local verifyfile  = process_opts["verify_filename"]
  local dumpram     = process_opts["dumpram"]
  local ramdumpfile = process_opts["ramdump_filename"]
  local writeram    = process_opts["writeram"]
  local ramwritefile= process_opts["writeram_filename"]

  local prg_size = console_opts["prg_rom_size_kb"]
  local chr_size = console_opts["chr_rom_size_kb"]
  local wram_size= console_opts["wram_size_kb"]

  dict.io("IO_RESET"); dict.io("NES_INIT")

  if test then
    print("Testing ", mapname)
    mirror_test(true)
    nes.ppu_ram_sense(0x1000, true)
    print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))
    prgrom_manf_id(true)
    chrrom_manf_id(true)
  end

  if dumpram then
    if not ramdumpfile or ramdumpfile == "" then
      print("[WARN] dumpram was requested but no ramdump_filename provided; skipping WRAM dump.")
    else
      print("Dumping WRAM...")
      init_mapper()
		mmc1_write(0xE000, 0x00)
		mmc1_write(0xA000, 0x02)
		mmc1_write(0xC000, 0x05)
      local f = assert(io.open(ramdumpfile, "wb"))
      dump_wram(f, wram_size, false) -- provided by host libs
		mmc1_write(0xE000, 0x10)
		mmc1_write(0xA000, 0x12)
		mmc1_write(0xC000, 0x15)
      assert(f:close())
      print("DONE Dumping WRAM")
    end
  end

  if read then
    if not dumpfile or dumpfile == "" then
      error("Read requested but dump_filename is missing (nil). Pass -d <path>.")
    end
    print("Dumping PRG & CHR ROMs...")
    init_mapper()
    local f = assert(io.open(dumpfile, "wb"))
    create_header(f, prg_size, chr_size)
    dump_prgrom(f, prg_size, false)
    dump_chrrom(f, chr_size, false)
    assert(f:close())
    print("DONE Dumping PRG & CHR ROMs")
  end

  if erase then
    print("erasing ", mapname)
    print("erasing PRG-ROM")
    dict.nes("NES_CPU_WR", 0xD555, 0xAA)
    dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
    dict.nes("NES_CPU_WR", 0xD555, 0x80)
    dict.nes("NES_CPU_WR", 0xD555, 0xAA)
    dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
    dict.nes("NES_CPU_WR", 0xD555, 0x10)
    local rv, i = dict.nes("NES_CPU_RD", 0x8000), 0
    while rv ~= 0xFF do rv = dict.nes("NES_CPU_RD", 0x8000); i = i + 1 end
    print(i, "naks, done erasing prg.")

    if chr_size ~= 0 then
      init_mapper()
      print("erasing CHR-ROM")
      dict.nes("NES_PPU_WR", 0x1555, 0xAA)
      dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
      dict.nes("NES_PPU_WR", 0x1555, 0x80)
      dict.nes("NES_PPU_WR", 0x1555, 0xAA)
      dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
      dict.nes("NES_PPU_WR", 0x1555, 0x10)
      rv, i = dict.nes("NES_PPU_RD", 0x8000), 0
      while rv ~= 0xFF do rv = dict.nes("NES_PPU_RD", 0x8000); i = i + 1 end
      print(i, "naks, done erasing chr.")
    end
  end

  if writeram then
    if not ramwritefile or ramwritefile == "" then
      print("[WARN] writeram was requested but no ramwrite_filename provided; skipping WRAM write.")
    else
      print("Writting to WRAM...")
      init_mapper()
      dict.nes("NES_MMC1_WR", 0xE000, 0x00)
      dict.nes("NES_MMC1_WR", 0xA000, 0x02)
      dict.nes("NES_MMC1_WR", 0xC000, 0x05)
      local f = assert(io.open(ramwritefile, "rb"))
      flash.write_file(f, wram_size, "NOVAR", "PRGRAM", false)
      dict.nes("NES_MMC1_WR", 0xE000, 0x10)
      dict.nes("NES_MMC1_WR", 0xA000, 0x12)
      dict.nes("NES_MMC1_WR", 0xC000, 0x15)
      assert(f:close())
      print("DONE Writting WRAM")
    end
  end

  if program then
    if not flashfile or flashfile == "" then
      error("Program requested but flash_filename is missing (nil). Pass -f <path> or similar.")
    end
    local f = assert(io.open(flashfile, "rb"))
    flash_prgrom(f, prg_size, false)
    flash_chrrom(f, chr_size, false)
    assert(f:close())
  end

  if verify then
    if not verifyfile or verifyfile == "" then
      print("[WARN] verify requested but no verify_filename; skipping post-dump verify output.")
    else
      print("Post dumping PRG & CHR ROMs...")
      init_mapper()
      local f = assert(io.open(verifyfile, "wb"))
      dump_prgrom(f, prg_size, false)
      dump_chrrom(f, chr_size, false)
      assert(f:close())
      print("DONE post dumping PRG & CHR ROMs")
    end
  end

  dict.io("IO_RESET")
end

-- ========= Export =========
mmc1.process = process
return mmc1
