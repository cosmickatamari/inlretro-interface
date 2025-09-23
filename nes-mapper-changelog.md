### CNROM:
*Problem:* `Adventure Island` (and some other CNROM games) looked scrambled because the dumper was writing bank numbers to the wrong addresses. On CNROM, if the ROM doesn’t contain `FF` at that spot, the number gets corrupted (bus conflict).

*Fix:*
1. Added a small helper that looks through the cartridge’s PRG ROM and finds a safe address that actually contains `FF`.
2. Changed the script so it only writes the bank number to that safe spot, instead of writing to a moving table of addresses.
3. Removed the extra writes that were causing the corruption.
<br/><br/>

### MMC1 edit 1 - `Final Fantasy`
*Problem:* Dumping produced header only and incorrect ROM size.

*Fix:*
1. Corrected the control register writes so MMC1 latched properly.
2. Ensured the PRG dump loop actually iterated through all PRG banks.
3. CHR handling was left intact since Final Fantasy has CHR-ROM.
<br/><br/>

### MMC1 edit 2 - `Blaster Master`
*Problem:* Original script only wrote header + `FF`, gave no video (sound only).

*Fix:*
1. Adjusted the PRG dumping order so that bank 0 was handled correctly and the fixed last bank was included.
2. Removed duplicate or redundant dump calls (previously overwriting the file or skipping banks).
3. Kept normal CHR dumping since Blaster Master has CHR-ROM.
<br/><br/>

### MHROM:
*Problem:* Mapper technically didn't exist, only one game for NES used this mapper `Super Mario Bros. & Duck Hunt` multicart `mapper 66 (GxROM/MHROM)`, not plain NROM, like originally assumed. Any attempt at trying `NROM` or `GTROM` would produce the correct sized ROM; however, Mesen would green screen with CPU crash. 

*Fix:*
1. Created a new mapper `MHROM.lua`
    - Implements proper bank switching for PRG and CHR.
    - PRG banks: 32 KB each, selected via bits 4–5 of the latch at `$8000–$FFFF`.
    - CHR banks: 8 KB each, selected via bits 0–1.
    - Correctly writes the iNES header with mapper ID `66`.

2. Integrated the new module:
    - Added `gxrom = require scripts.nes.mhrom` into `inlretro2.lua`’s mapper table.
    - Can be referenced with `-m GXROM`.
    - PowerShell frontend modified to reflect this change.
<br/>

Some code was adopted from this fork of the inlretro project from this LUA - https://gitlab.com/kevinms/INL-retro-progdump/-/blob/d936b8eac92c3206f13301a7df1ac5dd36699938/host/scripts/nes/gxrom.lua
<br/><br/>

### UNROM:
*Problem* `DuckTales (USA)` dumped; however would not load in Mesen. No data existed when viewing in a Hex Editor past the header row.

*Fix:*
1. Automatically detects the bank table location instead of using hardcoded addresses.
2. Uses bitwise logic to find safe write addresses that won't cause bus conflicts.
3. Has multiple fallback strategies if the primary method fails.
4. Forces proper UNROM mapper identification in the header
