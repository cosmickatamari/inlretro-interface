# NES Mapper Improvements - Detailed Changes

This document outlines the significant improvements made to the NES mapper scripts compared to the original versions. These changes improve compatibility with a wider range of NES cartridges, handle edge cases, and add support for new mapper types.

## Overview

The updated mapper scripts transform basic NES dumpers into robust tools that handle problematic cartridges, detect ROM configurations automatically, and provide multiple fallback strategies when standard approaches fail. The improvements focus on **automatic detection**, **bus conflict handling**, **game-specific fixes**, and **new mapper support**.

---

## Modified Mappers

### 1. CNROM (Mapper 3)

**What changed:**
The original CNROM script had issues with bus conflicts when writing bank selection values. The new version intelligently finds safe addresses to write bank values.

**Key improvements:**

- **Bus conflict detection** - New `find_ff_write_addr()` function scans PRG ROM space to find addresses containing `0xFF` bytes, which can be safely written without bus conflicts
- **Bank mask handling** - Properly handles CNROM variants with different numbers of bank bits (2-bit vs 4-bit)
- **Cleaner code structure** - Better organized with clearer comments

**Real-world impact:**
CNROM carts that previously failed due to bus conflicts now dump correctly. The automatic detection of safe write addresses eliminates the need for hardcoded bank table addresses.

---

### 2. MMC1 (Mapper 1)

**What changed:**
The original MMC1 script used a single dumping approach. The new version includes extensive debugging, multiple dumping strategies, and game-specific handling for problematic carts.

**Key improvements:**

- **Multiple dumping strategies** - Includes over 15 different dumping approaches:
  - Standard 32KB mode dumping
  - Mode 2 dumping (16KB switchable at $C000)
  - Direct memory reading
  - MMC3-style approach
  - Various community-sourced approaches (NESdev, Kevtris, emudev, etc.)
  - Power-on default state reading
  - Real NES power-on sequence simulation

- **Game detection** - `detect_mmc1_game_type()` function identifies problematic carts and selects appropriate dumping strategy

- **Battle of Olympus special handling** - Extensive special case handling for this notoriously difficult cart:
  - Tries SLROM configuration (CHR ROM, no WRAM)
  - Falls back to SNROM configuration (CHR RAM, WRAM)
  - Tests standard initialization
  - Attempts power-on default state
  - Mimics real NES power-on sequence
  - Falls back to manual byte-by-byte dumping

- **Fallback mechanism** - `dump_prgrom_with_fallback()` automatically detects if standard dumping produced invalid data (all 0xFF or 0x00) and retries with mode 2

- **Enhanced debugging** - Extensive debug output showing:
  - Bank selection verification
  - Test byte reads
  - Configuration testing results
  - Which approach is being used

**Real-world impact:**
Problematic MMC1 carts like Battle of Olympus that previously failed completely now have multiple fallback strategies. The extensive debugging makes it much easier to troubleshoot issues.

---

### 3. MMC3 (Mapper 4)

**What changed:**
The original MMC3 script had a single dumping approach. The new version includes game detection and custom dumping strategies for different games.

**Key improvements:**

- **Game detection** - `detect_game_type()` function reads initial bytes from PRG ROM to identify games:
  - Detects Super Mario 3 (uses standard approach)
  - Detects Mega Man 3 (uses custom approach)
  - Falls back to standard for unknown games

- **Custom dumping approach** - `dump_prgrom_custom()` function for games like Mega Man 3 and Astyanax:
  - More detailed bank selection verification
  - Test reads to verify bank switching
  - Uses standard dump method but with better verification

- **Dedicated dump initialization** - `init_mapper_dump()` function provides minimal, neutral setup specifically for dumping (different from flash programming setup)

- **Better header creation** - Manual header creation with proper iNES format, ensuring correct mapper and mirroring bits

**Real-world impact:**
Games like Mega Man 3 and Astyanax that previously dumped incorrectly now work reliably. The game detection automatically selects the right approach without manual intervention.

---

### 4. NROM (Mapper 0)

**What changed:**
The original NROM script assumed all carts were NROM-128 (16KB PRG). The new version automatically detects NROM-256 (32KB PRG) and handles both types correctly.

**Key improvements:**

- **NROM type detection** - `detect_nrom_type()` function:
  - Reads first 16KB and last 16KB of PRG ROM
  - Compares data to detect mirroring vs unique data
  - Automatically determines if cart is NROM-128 or NROM-256
  - Special handling for Son Son (forces NROM-256)

- **Automatic size detection** - Uses detected sizes instead of user-provided parameters:
  - `detected_prg_size` - Automatically set to 16KB or 32KB
  - `detected_chr_size` - Automatically detected (with forced 8KB for now)

- **Enhanced CHR ROM dumping** - Direct byte-by-byte reading with stability delays:
  - Reads each byte individually from PPU space
  - Adds small delays every 256 bytes for stability
  - Handles problematic carts like "Popeye no Eigo Asobi"

- **Mirroring detection** - Automatically selects correct mirroring:
  - NROM-256 uses horizontal mirroring (for Son Son)
  - NROM-128 uses detected mirroring

**Real-world impact:**
NROM-256 carts like Son Son that previously dumped incorrectly (showing mirrored data) now dump correctly with unique data. The automatic detection eliminates the need to manually specify ROM size.

---

### 5. UNROM/UxROM (Mapper 2)

**What changed:**
The original UNROM script had a hardcoded bank table address. The new version automatically searches for bank tables and includes fallback addresses.

**Key improvements:**

- **Automatic bank table detection** - `find_banktable()` function:
  - Searches fixed bank ($C000-$F000) for bank table signature
  - Constructs expected byte sequence (0x00, 0x01, 0x02, etc.)
  - Finds bank table location automatically

- **Fallback addresses** - If automatic detection fails, tries common bank table addresses:
  - `0xE473` (Owlia)
  - `0xCC84` (Nomolos)
  - `0x8000` (Rush'n Attack)
  - `0xC000` (Twin Dragons)
  - `0xFD69` (Armed for Battle)

- **Better debug output** - Shows:
  - Which bank table address is being used
  - Bank selection verification
  - Test reads to verify bank switching

- **Improved error handling** - Clear messages when bank table isn't found

**Real-world impact:**
UNROM carts with bank tables at non-standard locations now work automatically. The fallback addresses handle most common cases, eliminating the need to manually specify bank table addresses.

---

## New Mappers

### 6. MHROM/GxROM (Mapper 66)

**What it does:**
This is a completely new mapper implementation for iNES mapper 66, used by multicarts like Super Mario Bros./Duck Hunt.

**Features:**

- **Simple bank switching** - Uses single register at $8000-$FFFF:
  - Bits 4-5 select PRG-ROM bank (32KB banks)
  - Bits 0-1 select CHR-ROM bank (8KB banks)

- **Automatic mirroring detection** - Detects mirroring mode automatically

- **Clean implementation** - Straightforward dumping with proper bank selection

**Real-world impact:**
Multicarts using mapper 66 can now be dumped correctly. This mapper was previously unsupported.

---

### 7. NAMCOT-3415 (Mapper 2 variant)

**What it does:**
This is a specialized mapper implementation for Mappy-Land, which uses large ROMs (128KB PRG, 32KB CHR) with mapper 2.

**Features:**

- **Hardcoded Mappy-Land settings** - Forces NROM-256 mode with specific sizes:
  - 128KB PRG ROM
  - 32KB CHR ROM
  - Vertical mirroring

- **Simple dumping approach** - Uses straightforward 32KB chunks for PRG ROM

- **Standard CHR ROM reading** - Uses standard PPU reading for CHR ROM

**Real-world impact:**
Mappy-Land can not be dumped correctly. 

---

## Technical Details

### Bus Conflict Handling

One of the trickier issues handled is bus conflicts in CNROM. When writing bank selection values, if the ROM byte at that address isn't `0xFF`, the ROM and MCU can conflict. The solution:

1. Scan PRG ROM space (`$8000-$FFFF`) to find addresses containing `0xFF`
2. Use those addresses for bank selection writes
3. Apply bank mask to respect the actual number of bank bits

This eliminates the need for hardcoded bank table addresses and works with any CNROM variant.

### MMC1 Serial Interface Handling

MMC1 uses a serial shift register interface that requires 5 writes to load a register. The new MMC1 script includes multiple approaches:

- **Standard approach** - Uses firmware `NES_MMC1_WR` which handles the serial interface
- **Manual 5-write sequences** - Various implementations that manually perform the 5-write sequence
- **Mode detection** - Automatically detects which PRG ROM mode works for each cart

The extensive fallback strategies ensure that even problematic carts eventually get dumped successfully.

### Game-Specific Detection

Both MMC1 and MMC3 include game detection that reads initial bytes from PRG ROM to identify problematic games:

- **Signature matching** - Looks for known byte patterns
- **Pattern detection** - Identifies common instruction patterns (JMP, JSR)
- **Automatic strategy selection** - Chooses appropriate dumping approach

This makes the dumpers "smart" - they automatically adapt to different games without manual configuration.

---

## Code Quality Improvements

### Better Error Handling

All mappers now include:
- Clear error messages when operations fail
- Fallback strategies when primary approach fails
- Validation of dumped data (checking for all 0xFF or 0x00)

### Enhanced Debugging

Extensive debug output including:
- Bank selection verification
- Test byte reads
- Which approach is being used
- Progress indicators

### Cleaner Code Structure

- Better function organization
- Clearer comments explaining mapper behavior
- Consistent naming conventions
- Proper module exports

---

## Known Limitations and Future Improvements

While the current versions handle many edge cases, there are still opportunities for improvement:

1. **More game-specific handlers** - Additional games may need special handling as they're encountered
2. **Better CHR RAM detection** - Some mappers could better detect CHR RAM vs CHR ROM
3. **Flash programming improvements** - Flash programming code could be enhanced with better error handling
4. **More mapper variants** - Additional mapper variants could be added as needed

---

## Testing Recommendations

If you're working on improvements, here are some games that make good test cases:

- **Son Son** - NROM-256 detection
- **Battle of Olympus** - MMC1 problematic cart
- **Mega Man 3** - MMC3 custom approach
- **Super Mario Bros./Duck Hunt** - MHROM/GxROM mapper 66
- **Mappy-Land** - NAMCOT-3415 large ROMs
- **Various CNROM games** - Bus conflict handling

---

## Summary

The updated NES mapper scripts are significantly more robust than the originals. They handle edge cases that would previously cause failures, automatically detect ROM configurations, and include extensive fallback strategies for problematic carts. The code is also more maintainable and easier to extend with additional game-specific handlers or mapper support.

If you're picking up this codebase, the main areas to focus on for further improvements would be:
- Adding more game-specific handlers as problematic carts are encountered
- Improving CHR RAM/ROM detection
- Adding support for additional mapper variants
- Enhancing flash programming reliability

The foundation is solid and ready for these kinds of enhancements.

