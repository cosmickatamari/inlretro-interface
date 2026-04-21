### Commited Changes

**11/11/2025 `(.\host\archive\inlretro-interface-10m.ps1)`**
1. Moved the default file size to after header parser correcting the issue of all SNES cartridge dumps being 4mb. 
	- This is only needed if the header parsing fails.
	- This also fixed `Super Mario Kart` from not executing in Mesen past the title screen.
2. Put in logic to where when the SRAM is detected and there are additional possible methods for detecting the SRAM, they are not run.
3. More display cleanup and easier to read messages.
4. Took out all the extra title specific checks for games like `Super Mario World 2: Yoshi's Island`, since they can properly be detected now with the default logic for `Super FX` chips.
5. Output is captured to temp files for parsing; counter updates in real time.
	- This results in faster completion at the end during the process summary.
6. Provide the game ROM and the SRAM location, size and signatures on the screen at the end of the process.
	- Mainly meant for troubleshooting or verification.
7. Better error handling cleanup if there's a hardware or syntax error.
	- Program now force quits instead of attempting to continue process.
8. Cleaner game ROM and SRAM dump process on the screen.
	- Prints every 8 banks instead of every bank.
9. Friendlier looking UI during the cartridge dump to make sections easier to understand.
10. Log file output was updated to give a better history of game cartridge processes and status.
11. SRAM detection methods were cleaned up and will no longer run sections that aren't needed after the required SRAM information has been detected.
12. Fixed I/O lag that was taking place during the cartridge detection, improving speeds.
	- `Super Mario World 2: Yoshi's Island` went from 61 seconds to 21 seconds.
13. Fixed missing closing brace syntax error in `Invoke-INLRetro` function.
	- I'm still unsure how the script was running with a syntax error.
14. Adjusted step 1 in the cart detection to only treat `SRAM` as present when a numeric size is parsed (ex, "SRAM Size: 32K" or "256 kilobits" → 32KB). 
	- This fixed false positives on non-battery games.
15. Corrected `map_mode_desc` so common values display "`LoROM FastROM"/"HiROM FastROM`" instead of misleading "`+ EXHIROMSA1`".
16. After a game cartridge is dumped, made input faster to keep dumping cartridges.
	- Pressing [Enter] will default to `No` for the following:
		- "Would you like to access the RetroRGB.com article on cleaning best practices? (y/n)"
		- "Proceed with another attempt? (An incremental version will be made.) (y/n)"
	- Messages were rewritten to reflect default choices of 'n'.
17. More adjustments to the headers parsing as `Pinoccino` was trying to originally dump as a `LoROM (SlowROM)` when it's actually a `HiROM (FastROM)`.
18. Created a padding check and message for games like `[Disney's] Toy Story` where the first 66 bytes are `00`.
19. For some SRAM issues, especially with `SimEarth: The Living Planet` scan the entire SRAM window for save signatures.
	- The should help with games with non-standard offsets.
20. Removed the default `SA-1` fallback.
	- This was for troubleshooting `Super Mario RPG: Legend of the Seven Stars`.
	- `SA-1` detection doesn't seem to be working, might be a firmware limitation?
21. Implemented save signature detection for `SimEarth: The Living Planet`. 
	- Any modification caused `Lemmings 2: The Tribes` to lose ability to save SRAM.
22. SRAM signature search for `SimEarth: The Living Planet` with `TOMCAT` in the entire 32k bank.
	- Once found, the memory is dumped to an SRAM file.
23. Updated `string_from_bytes` to generate cleaner ROM title strings by handling null-terminated strings, avoiding display issues from control characters, and removing extra whitespace.
24. Added the special case for map mode `0x44` to the mappingfrommapmode function in v2lua. 
	- Map mode `0x44` detection: Games like `Robotrek` and `Brain Lord` (which use the `SHVC-2J3M-11` PCB) are detected as `HiROM` even though bit 0 is 0, which normally indicates `LoROM`.
25. Updated the `isvalidheader` function in v2lua with the relaxed validation. 
	- Only checks essential fields: 
		- `rom_type` must be in the `hardware_type` table
		- `rom_size` must be in the `rom_size_kb_tbl` table.
		- Removed checks for `destination_code`, `sram_size`, and `non-zero` rom_size.
		- More tolerant of dirty or badly seated carts that may omit or have corrupted header fields. (Clean your carts!)
26. Changed `dump_rom` function to now validates ROM size before dumping and more accurately detects LoROM FastROM games (ex. `Super Mario World 2: Yoshi's Island`) by checking both the upper bits and bit 0 of the map mode.
27. Mapper string normalization (case-insensitive):
	- This will really only matter if you manually run a dump command from the command line.
	- Normalized mapper strings (for manual CLI commands) to match constants regardless of case:
		- Converts `HiROM`, `hirom`, `HIROM` to hirom_name.
		- Converts `LoROM`, `lorom`, `LOROM` to lorom_name.
28. Better `HiROM` bank selection based on ROM size.
	- Selects `HiROM` bank based on ROM size after header detection
		- ROMs ≤ 4MB: use banks `0x80-0xBF` (first 4MB, fast ROM).
		- ROMs > 4MB: use banks `0xC0-0xFF` (second 4MB, fast ROM).
29. Changed the initial `HiROM` default from slow ROM bank `0x40` to fast ROM bank `0x80` to match most games. 
	- It will be corrected after header detection if the ROM is larger than 4MB.
30. ROM size fallback handling:
	- Adds fallback when header provides invalid/unknown ROM size, defaulting to 1024KB (1MB) if ROM size is nil or 0.
31. Fixed the detection loop with `SimEarth: The Living Planet` where the `dump_ram` progress didn't show on the screen.
32. Formatting changes to the log file.
33. Application now quits if the Mask ROM detection fails.
	- Otherwise it would generate a faulty ROM/SRAM dump, which would be a waste of time.
34. Cleaned up some more error handling logic.
35. Created caution messages about potentially good SRAM dumps with `00` for the file signature.
