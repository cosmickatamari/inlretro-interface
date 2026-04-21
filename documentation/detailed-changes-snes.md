# SNES ROM Dumper Improvements - v2proto_hirom.lua

This document outlines the significant improvements made to the SNES ROM dumper/programmer module (`v2proto_hirom.lua`) compared to the original version. These changes were made to improve compatibility with a wider range of SNES cartridges, especially those with non-standard configurations or special hardware.

## Overview

The updated version transforms a basic SNES dumper into a robust tool that handles edge cases, special hardware configurations, and games with unusual SRAM mapping. The improvements focus on three main areas: **header detection**, **SRAM dumping**, and **game-specific handling**.

---

## Major Improvements

### 1. Enhanced Header Detection (`test()` function)

**What changed:**
The original version tried exactly two configurations (HiROM at 0x0000, LoROM at 0x8000) without setting banks or initializing the cartridge. The new version is much more thorough.

**Why it matters:**
Many SNES games, especially LoROM FastROM titles like Ultima: False Prophet, need specific bank addresses to be set before the header can be read. Without proper initialization, these games would fail to detect.

**What it does now:**
- **Initializes the cartridge** by calling `snes.play_mode()` and adding proper delays
- **Tries multiple bank configurations** systematically:
  - Bank 0x00 (most common for both LoROM and HiROM)
  - Bank 0x80 (FastROM games)
  - Bank 0xC0 (SlowROM games, needed for Robotrek/Brain Lord)
  - Bank 0x40 (edge cases)
- **Retries with longer delays** if the first attempt fails
- **Provides helpful error messages** with troubleshooting tips

**Real-world impact:**
Games like Ultima: False Prophet that previously failed header detection now work reliably. The retry logic also helps with cartridges that need a moment to stabilize after insertion.

---

### 2. Smarter Header Validation (`isvalidheader()` function)

**What changed:**
The original version required four fields to be valid: ROM type, ROM size, SRAM size, and destination code. This was too strict for many cartridges.

**Why it matters:**
Prototype cartridges, damaged headers, or games with non-standard configurations (like Robotrek with map mode 0x44) would fail validation even though they're perfectly valid cartridges.

**What it does now:**
- **Relaxed validation** - only checks ROM type and ROM size (the essential fields)
- **Special case for map mode 0x44** - automatically accepts headers with this map mode, which is used by SHVC-2J3M-11 PCB games like Robotrek and Brain Lord
- **More forgiving** - doesn't require SRAM size or destination code to be valid

**Real-world impact:**
Games with corrupted or non-standard headers that would previously be rejected are now detected correctly. This is especially important for prototype cartridges or games with unusual PCB configurations.

---

### 3. Special Game Handling

**What changed:**
The original version had no special handling for games with unusual SRAM configurations. The new version includes dedicated functions for several problematic games.

**EarthBound (Mother 2):**
- Uses a completely non-standard SRAM location: bank 0x30, offset 0x0060 (not the usual 0x6000)
- Requires `SNESSYS_PAGE` instead of the standard page type
- Now automatically detected and handled correctly

**SimEarth:**
- Uses a TOMCAT signature system where the actual SRAM data can be anywhere in a 32KB window
- The code searches for the "TOMCAT" signature (hex: 54 4F 4D 43 41 54) and extracts the SRAM from that location
- Includes fallback logic if the signature isn't found
- Much more robust than the original simple dump

**The 7th Saga:**
- HiROM game that uses LoROM-style SRAM mapping (bank 0x70, offset 0x8000)
- Requires `SNESROM_PAGE` instead of `SNESSYS_PAGE`
- Now automatically detected by testing standard HiROM location first, then falling back to LoROM-style if needed

**Real-world impact:**
These games previously produced corrupted or empty SRAM dumps. Now they dump correctly and work in emulators.

---

### 4. Improved SRAM Detection for HiROM Games

**What changed:**
The original version assumed all HiROM games use bank 0x30 with offset 0x6000. Some HiROM games (like The 7th Saga) actually use LoROM-style SRAM banks.

**What it does now:**
- Tests the standard HiROM location first (bank 0x30, offset 0x6000)
- If that appears unmapped (all 0xFF), automatically tries LoROM-style location (bank 0x70, offset 0x8000)
- Uses the correct page type (`SNESROM_PAGE` vs `SNESSYS_PAGE`) based on what was detected
- Enables LoROM-style SRAM banks via MAD-1 register when needed

**Real-world impact:**
HiROM games with non-standard SRAM mapping now dump correctly without manual intervention.

---

### 5. Expanded Hardware Type Support

**What changed:**
The original version only had 7 hardware types defined. The new version includes 18 hardware types covering most SNES enhancement chips.

**New hardware types added:**
- SuperFX variants (0x13, 0x15, 0x19, 0x1A)
- Third-party ROM configurations (0x20, 0x21)
- Majesco variants (0x30, 0x31)
- SA-1 chip (0x33)
- S-DD1 chip (0x43)
- CX4 chip (0xF3)
- DSP2 chip (0xF6)

**Real-world impact:**
Games using these enhancement chips are now properly identified and can have appropriate handling added if needed.

---

### 6. Better ROM Size Handling

**What changed:**
The original version calculated ROM sizes using `2 * 128` style math. The new version uses direct KB values with clear comments.

**Improvements:**
- More readable code (256 KB vs `2 * 128`)
- Added support for 512 kilobits SRAM (64 KB)
- Better fallback handling when ROM size is unknown (defaults to 1MB instead of crashing)

**Real-world impact:**
Easier to maintain and understand. Unknown ROM sizes no longer cause crashes.

---

### 7. Enhanced Developer Code Database

**What changed:**
The original version had a good developer code list, but the new version is more comprehensive and includes better formatting.

**Real-world impact:**
Better identification of game publishers/manufacturers when dumping cartridges.

---

### 8. Improved Error Handling and Debugging

**What changed:**
The original version had minimal error messages. The new version provides detailed feedback.

**Improvements:**
- Helpful error messages when header detection fails
- Debug output showing which banks/configurations are being tried
- Better handling of edge cases (empty SRAM, file I/O failures)
- Prevents infinite loops in flash erase operations

**Real-world impact:**
Much easier to troubleshoot when something goes wrong. You can see exactly what the code is trying and why it might be failing.

---

### 9. Code Quality Improvements

**What changed:**
The code structure was improved for maintainability.

**Improvements:**
- Added delay constants (`DELAY_BANK_SWITCH`, `DELAY_CHIP_STOP`, `DELAY_REGISTER_SETUP`) instead of hardcoded values
- Better function documentation with parameter descriptions
- More consistent naming conventions
- Helper functions for common operations (`wait_delay()`)
- Better string handling (improved `string_from_bytes()` function)

**Real-world impact:**
Easier to maintain and extend. Future improvements can be made more confidently.

---

### 10. SuperFX Chip Handling

**What changed:**
The original version had no SuperFX chip handling. The new version includes functions to stop the GSU chip before ROM dumping.

**What it does:**
- Detects SuperFX games by hardware type or ROM title
- Stops the GSU processor before ROM dumping to prevent interference
- Configures the chip for ROM access mode
- Handles both LoROM and HiROM SuperFX games correctly

**Real-world impact:**
SuperFX games (like Stunt Race FX) now dump reliably without interference from the enhancement chip. Star Fox does not correctly dump at this time.

---

## Technical Details

### Map Mode 0x44 Special Handling

One of the trickier issues handled is map mode 0x44, used by SHVC-2J3M-11 PCB games like Robotrek and Brain Lord. These games are HiROM but the map mode byte has bit 0 cleared, which would normally indicate LoROM. The code now:

1. Checks for map mode 0x44 specifically in `mappingfrommapmode()`
2. Accepts headers with map mode 0x44 even if ROM type/size are invalid
3. Tries bank 0xC0 during header detection (where these games often have their headers)

### SRAM Detection Logic

For HiROM games, the code now:
1. Enables LoROM-style SRAM banks via MAD-1 register (safe to do even if not needed)
2. Tests standard HiROM location (bank 0x30, offset 0x6000)
3. If that's all 0xFF, tests LoROM-style location (bank 0x70, offset 0x8000)
4. Uses the correct page type based on what was detected

This handles games like The 7th Saga that are HiROM but use LoROM-style SRAM mapping.

---

## Known Limitations and Future Improvements

While the current version handles many edge cases, there are still opportunities for improvement:

1. **More game-specific handlers** - Games like SimAnt (32KB SRAM with TOMCAT signature) could benefit from dedicated handling
2. **Better SRAM size autodetection** - Some games report incorrect SRAM sizes in headers
3. **Support for more enhancement chips** - SA-1, S-DD1, and CX4 games might need special handling
4. **Flash programming improvements** - The flash programming code could be enhanced with better error handling

---

## Testing Recommendations

If you're working on improvements, here are some games that make good test cases:

- **Ultima: False Prophet** - LoROM FastROM, tests header detection
- **The 7th Saga** - HiROM with LoROM-style SRAM, tests SRAM detection
- **Robotrek** - Map mode 0x44, tests special map mode handling
- **EarthBound** - Non-standard SRAM location, tests game-specific handler
- **SimEarth** - TOMCAT signature search, tests complex SRAM extraction
- **Star Fox** - SuperFX chip, tests enhancement chip handling

---

## Summary

The updated `v2proto_hirom.lua` is significantly more robust than the original. It handles edge cases that would previously cause failures, provides better error messages for troubleshooting, and includes special handling for games with unusual configurations. The code is also more maintainable and easier to extend with additional game-specific handlers or hardware support.

If you're picking up this codebase, the main areas to focus on for further improvements would be:
- Adding more game-specific SRAM handlers as needed
- Improving SRAM size autodetection for edge cases
- Adding support for additional enhancement chips
- Enhancing flash programming reliability

The foundation is solid and ready for these kinds of enhancements.

