Changes to the file `host\scripts\snes\v2proto_hirom.lua` release introduces significant improvements to documentation, hardware-type support, ROM/SRAM handling, SuperFX processing (well... kinda), and special-case game handling. Numerous bug fixes, structure changes, and quality-of-life updates enhance maintainability, robustness, and compatibility.


<br/><br/>
1. Expanded special-case game support:
	- EarthBound (Mother 2) — special SRAM extraction
	- SimEarth — signature-based SRAM extraction
	- SuperFX (`GSU-2`) chip integration.
		- `Mario Chip`, `GSU-1` had additional issues not yet fully fixed.
	- Automatic GSU shutdown during ROM dump/verify.
	- Detection via hardware type or title
	- Added support for additional hardware types including `DSP1`.
	- Added `map_mode_desc` index (25+ entries).

2. Documentation / Code Structure:
	- Added module header description and supported special-case notes.
	- Reorganized file into functional sections:
		- Utility
		- Header Parsing
		- Flash ROM
		- Special Chips
		- ROM Dumping / SRAM Dumping
		- Main Process
		
3. Standardized constants:
	- hirom_name/lorom_name → HIROM_NAME/LOROM_NAME

4. Added timing constants:
	- DELAY_BANK_SWITCH, 
	- DELAY_CHIP_STOP, 
	- DELAY_REGISTER_SETUP

5. ROM / SRAM Handling:
	- Corrected ROM size math (256 KB granularity).
	- Added SRAM size 0x06 (512 kbit / 64 KB).
	- Updated map-mode handling for `SHVC-2J3M-11` boards.
	- Header Parsing
	- Improved `print_header()`:
		- Displays map mode descriptions
		- Adds expansion RAM size
		- Formats version as X.Y
	- `isvalidheader()` relaxed to support proto/odd carts.
	- LoROM detection prioritized for FastROM.
	- Added map mode 0x44 handling.
	- String Processing

6. Improved string_from_bytes():
	- Stops at null terminators
	- Filters non-printable characters
	- Replaces control codes with spaces
	- Trims trailing whitespace
	- Simplified `seq_read()` loop.
	- ROM / RAM Dumping

7. dump_rom():
	- Validates ROM size
	- Handles FastROM misclassification
	- Improved error reporting

8. dump_ram():
	- Early exit if no RAM
	- EarthBound and SimEarth special handling
	- Better progress reporting
	- Added bank-switch delay
	- Main Process
	- Normalized mapper input (case-insensitive).
	- HiROM default bank changed from `0xC0 → 0x80` for ≤4MB.
	- SRAM determination improved for `GSU-1`.
	- ROM size fallback to 1024 KB for invalid headers.
	- Fixed flashfile / verifyfile option usage.
	- Updated UI references from “SNES” → “Super Nintendo”.

9. Miscellaneous
	- Code formatting improvements.
	- More descriptive error messages.
	- Cleanup of `wr_ram()`.

10. Bug Fixes
	- Corrected ROM size miscalculation.
	- Fixed incorrect handling of flashfile/verifyfile.
	- Improved `HiROM/LoROM` misdetection recovery.
	- Relaxed header validation removed false failures.
	- Eliminated commented dead code in `wr_ram()`.


<br/><br/>
### Technical Summary:
1. Better special-case handling for SuperFX, EarthBound, and SimEarth.
2. Improved mapping normalization and bank selection logic.
3. Adds hardware type, ROM/SRAM, and map mode coverage.
4. Increases reliability of ROM/RAM dumping and header parsing.