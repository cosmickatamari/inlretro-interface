# SA-1 Cartridge Support Limitations for INL Retro Dumper

## Executive Summary

SA-1 enhanced Super Nintendo cartridges (such as Kirby Super Star, Super Mario RPG, and others) **cannot currently be detected or dumped** using the INL Retro dumper due to hardware-level CIC (Copy Protection Integrated Circuit) authentication requirements. The SA-1 chip sits between the cartridge connector and ROM chips, blocking all ROM access until it receives proper SNES CIC authentication signals.

## What is SA-1?

The SA-1 (Satellaview CPU) is an enhancement chip used in approximately 20 Super Nintendo games. It contains:
- A CPU running at 10.74 MHz (3x faster than the SNES's 3.58 MHz CPU)
- 2KB of fast internal RAM
- DSP functions
- **CIC lockout functionality** - This is the critical limitation

Unlike previous SNES CIC chips that prevented counterfeit consoles from playing genuine games, SA-1 games also prevent genuine games from working in counterfeit consoles. The SA-1 chip actively blocks ROM access until it receives proper CIC authentication.

## The Core Problem

The SA-1 chip requires **SNES CIC authentication** to unlock ROM access. When attempting to read from SA-1 cartridges without proper CIC authentication:

- All ROM reads return `0xFF` (uninitialized/floating bus state)
- Header detection fails completely
- No cartridge information can be retrieved
- ROM dumping is impossible

This is a **hardware-level limitation** - the SA-1 chip physically blocks access to the ROM chips until it receives the correct authentication sequence from a genuine SNES CIC.

## Attempts Made to Enable SA-1 Support

Multiple software-based approaches were attempted to work around the CIC authentication requirement:

### 1. DX2 Trick Implementation
**What it is:** A technique from uCON64 that involves rapidly toggling the cartridge between reset mode and play mode multiple times with specific timing.

**Implementation:**
- Toggled `prgm_mode()` and `play_mode()` 5-11 times with varying delays (0.005s to 0.02s)
- Tested ROM accessibility immediately after each toggle pair
- Attempted multiple toggle sequences (up to 3 attempts per session)

**Result:** ❌ Failed - All ROM reads still returned `0xFF`

### 2. CLK1 (M2/SYSCLK) Clock Signal Disabling
**What it is:** Attempting to disable the system clock signal (CLK1/M2) during initialization, as some sources suggest this can improve unlocking.

**Implementation:**
- Used `dict.pinport("CTL_OP", "M2")` and `dict.pinport("CTL_SET_LO", "M2")` to disable clock
- Performed toggle sequences with clock disabled
- Re-enabled clock after each attempt
- Tested both with and without clock disabled

**Result:** ❌ Failed - No improvement in ROM access

### 3. Systematic Bank Scanning
**What it is:** Testing all possible ROM banks (0x00-0x7F) systematically to find any accessible ROM region.

**Implementation:**
- Scanned all 128 banks (0x00-0x7F) where SA-1 ROM should be mapped
- Tested 8 different addresses per bank (0x7FC0, 0x8000, 0x0000, 0x7FFF, 0x0001, 0x8001, 0x7F00, 0x8100)
- Total of 1,024 read attempts per scan
- Performed before and after toggle sequences

**Result:** ❌ Failed - All 1,024+ read attempts returned `0xFF`

### 4. Progressive Timing Variations
**What it is:** Trying different delay timings between reset/play mode toggles.

**Implementation:**
- Started with 0.005s delays
- Progressively increased to 0.01s, 0.015s, 0.02s delays
- Increased toggle counts from 5 to 8 to 11 per sequence
- Multiple stabilization delays (0.05s to 0.1s)

**Result:** ❌ Failed - No combination of timings enabled ROM access

### 5. Multiple Bank and Address Testing
**What it is:** Testing ROM accessibility at various banks and addresses immediately after toggle sequences.

**Implementation:**
- Tested banks: 0x00, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70
- Tested addresses: 0x7FC0 (LoROM header), 0x8000, 0x0000, 0xFFC0 (HiROM header)
- Tested during toggle sequences (after toggle pairs 3, 4, and 5)
- Tested after complete toggle sequences

**Result:** ❌ Failed - All reads returned `0xFF` regardless of bank or address

## Why These Attempts Failed

All software-based approaches failed because they cannot address the fundamental requirement: **SNES CIC authentication**. The SA-1 chip requires:

1. **Proper CIC communication protocol** - The INLretro hardware does not appear to have SNES CIC emulation/cloning capability
2. **Timing-critical authentication sequence** - CIC authentication involves precise timing of clock and data signals
3. **Hardware-level CIC clone** - Similar to how Retrode required a dedicated CIC clone adapter

## Comparison with Other Hardware

**Retrode (AVR-based dumper):**
- Initially could not dump SA-1 games
- Required a community-developed plug-in adapter containing:
  - Dedicated timing source
  - PIC microcontroller programmed as a CIC clone
- Required firmware updates to work with the adapter
- Successfully enabled SA-1 dumping only after hardware modification

**INLretro (STM32-based dumper):**
- Currently lacks SNES CIC emulation/cloning capability
- Software-only approaches insufficient
- Would require similar hardware/firmware support for SA-1 games

## What Would Be Required for SA-1 Support

To enable SA-1 cartridge support, the INLretro hardware would need:

1. **SNES CIC Emulation/Cloning**
   - Hardware implementation of SNES CIC authentication protocol
   - Proper timing control for CIC clock and data signals
   - Ability to generate correct authentication sequences

2. **Firmware Updates**
   - CIC communication routines
   - SA-1-specific initialization sequences
   - Integration with existing dumping routines

3. **Possible Hardware Modifications**
   - Additional control signals for CIC communication
   - Dedicated CIC clone chip (similar to Retrode adapter)
   - Enhanced timing capabilities

## Current Status

**SA-1 cartridges are NOT supported** by the INLretro dumper. When attempting to detect SA-1 cartridges:

- Detection phase fails immediately
- All ROM reads return `0xFF`
- Error message displayed: "The cartridge's Mask ROM can not be detected."
- Informative error message explains CIC authentication requirement

## Affected Games

Approximately 20 SNES games use the SA-1 chip, including:
- Kirby Super Star
- Super Mario RPG: Legend of the Seven Stars
- Jikkyou Oshaberi Parodius
- SD Gundam GX
- And others

## Recommendations

1. **Check for firmware updates** - Contact INLretro developers to inquire about SA-1/CIC support plans
2. **Use alternative hardware** - For SA-1 games, consider using Retrode with CIC clone adapter or other hardware with CIC support
3. **Manual ROM size specification** - If firmware adds SA-1 support but detection still fails, manual ROM size specification may be possible

## Conclusion

SA-1 cartridge support requires hardware-level SNES CIC authentication capabilities that the current INLretro hardware does not possess. All software-based workarounds (DX2 trick, clock manipulation, bank scanning, timing variations) failed because they cannot bypass the CIC authentication requirement. Support for SA-1 cartridges would require significant hardware and/or firmware enhancements to the INLretro dumper.

---

**Date:** December 2024  
**Tested with:** Kirby Super Star (SA-1 cartridge)  
**INLretro Firmware Version:** 2.3.x  
**Interface Script Version:** inlretro-interface-10m.ps1

