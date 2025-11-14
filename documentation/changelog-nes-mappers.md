### CNROM:
*Issue:* `Adventure Island` (and some other CNROM games) looked scrambled because the dumper was writing bank numbers to the wrong addresses. On CNROM, if the ROM doesn’t contain `FF` at that spot, the number gets corrupted (bus conflict).

*Resolution:*
1. Added a small helper that looks through the cartridge’s PRG ROM and finds a safe address that actually contains `FF`.
2. Changed the script so it only writes the bank number to that safe spot, instead of writing to a moving table of addresses.
3. Removed the extra writes that were causing the corruption.
<br/><br/>

### MHROM:
*Issue:* Mapper technically didn't exist, only one game for NES used this mapper `Super Mario Bros. & Duck Hunt` multicart `mapper 66 (GxROM/MHROM)`, not plain NROM, like originally assumed. Any attempt at trying `NROM` or `GTROM` would produce the correct sized ROM; however, Mesen would green screen with CPU crash. 

*Resolution:*
1. Created a new mapper `MHROM.lua`
    - Implements proper bank switching for PRG and CHR.
    - PRG banks: 32 KB each, selected via bits 4–5 of the latch at `$8000–$FFFF`.
    - CHR banks: 8 KB each, selected via bits 0–1.
    - Correctly writes the iNES header with mapper ID `66`.

2. Integrated the new module:
    - Added `gxrom = require scripts.nes.mhrom` into `inlretro2.lua`’s mapper table.
    - Can be referenced with `-m GXROM`.
    - PowerShell frontend modified to reflect this change.

Some code was adopted from this fork of the inlretro project from this LUA - https://gitlab.com/kevinms/INL-retro-progdump/-/blob/d936b8eac92c3206f13301a7df1ac5dd36699938/host/scripts/nes/gxrom.lua
<br/><br/>

### MMC1 – Edit 1: `Final Fantasy`
*Issue:* Dumping produced only the header and an incorrect ROM size.

*Resolution:*
1. Corrected control register writes to ensure proper MMC1 latching.
2. Fixed the PRG dump loop to iterate through all PRG banks.
3. Left CHR handling unchanged, as Final Fantasy uses CHR-ROM.
<br/><br/>

### MMC1 – Edit 2: `Blaster Master`
*Issue:* Original script produced only the header followed by FF padding. Resulting dump had audio but no video.

*Resolution:*
1. Corrected PRG dump sequence so that bank 0 was handled correctly and the fixed last bank was included.
2. Removed redundant or duplicate dump calls that previously overwrote or skipped banks.
3. Retained standard CHR handling, as Blaster Master uses CHR-ROM.
<br/><br/>

### MMC3 - `Mega Man 3`
*Issue:* Similar to previous cases, the mapper was not correctly accessing the PRG banks. While the header row was read and written properly, subsequent data was either incorrect or absent. Hex editor inspection revealed that all bytes beyond the header were filled with `FF`.

*Resolution:*
1. Implemented custom dumping routines optimized for specific, identified titles to ensure accurate ROM extraction.
<br/><br/>

### MMC1 - Edit 2
*Issue:* Subsequent fixes applied to support one title occasionally introduced regressions in previously corrected mapper behavior, causing other games to fail their ROM dumps.

*Resolution:*
1. Preserved full compatibility with standard MMC3 implementations.
2. Added fallback mechanisms to handle unidentified or unsupported games gracefully.
<br/><br/>

### NROM
*Issue:* `Balloon Fight` cartridge failed to return valid PRG/CHR data beyond the iNES header, producing an incomplete ROM dump.

*Resolution:*
1. Corrected an invalid variable reference. The original code attempted to access `op_buffer[mapname]` directly, but op_buffer was not defined in the local scope.
2. Introduced proper namespace resolution by referencing `dict.op_buffer[mapname]`, ensuring the property is accessed correctly from the dict module.
<br/><br/>

### UNROM – Edit 1: `DuckTales`
*Issue:* Dump completed successfully; however, the resulting ROM image failed to execute in Mesen. Hex inspection revealed that no PRG/CHR data was present beyond the iNES header.

*Resolution:*
1. Implemented automatic detection of the bank table rather than relying on hardcoded addresses.
2. Introduced bitwise logic to determine safe write addresses, avoiding bus conflicts.
3. Added multiple fallback strategies if primary detection fails.
4. Forced proper UNROM mapper identification in the ROM header.
<br/><br/>

### UNROM – Edit 2: `DuckTales` and `Castlevania`
*Issue:* During the second validation cycle, the `DuckTales` cartridge encountered errors in bank table access, preventing correct PRG/CHR mapping.

*Resolution:*
1. Implemented a debugger, which consistently reported: `Bank    0       test read @ $8000:      FF FF FF FF FF FF FF FF` across all banks.
2. Identified incorrect bank selection at $C000; corrected to use the $8000–$BFFF address range.
3. Verified fix against all available UNROM titles in the collection (`Top Gun`, `Mega Man`, `DuckTales`, `Castlevania`).
<br/><br/>

### NROM - Edit 2: `Son Son` and `Spelunker` (Famicom)
*Issue:* `Son Son` and `Spelunker` cartridges failed to provide valid data past the iNES header, resulting in truncated and incomplete ROM dumps.

*Resolution:*
1. Implemented `NROM-256` detection, as Famicom cartridges commonly use 256 KB instead of 128 KB.
2. Added PPU reinitialization between CHR ROM passes to ensure proper graphics data handling.
3. Disabled vector patching logic, which was identified as the source of runtime crashes.
4. Corrected mirroring detection logic: `Son Son` now properly maps with horizontal mirroring, and `Spelunker` with vertical mirroring.
