### Commited Changes

**12/27/2025 `(inlretro-interface-0.10q.ps1)`**
1. Moved detection temp files from `.\host` to `.\ignore`.
2. Folder check for `ignore` when detection method begins, the folder is also deleted when the program is gracefully exited.
3. The session time and amount stats were added during the redump phase, just as the first run.
4. Various workflow tweaks attempting to optimize speed whenever dumping cartridges with 32 megabits.
5. Resolved some query issues with the header information.
6. Resolved issue with `Write-FileAnalysisLines` when being called and having an empty array. 
7. Needed to adjust for `00` padding in game ROM.
8. Spent sometime for **much better code commenting**, in the event someone else wants to modify anything. And for sanity sake!
9. Modularized the PowerShell script into separate module files. 
	- Based on functions and consoles but grouped by similar processes. 
	- Located in the `.\modules\` folder.
	- Names start with `INLinterface.*`
	- Most modules need to start at the beginning; however, console specific modules are on-demand whenever that console is being used to dump a cartridge.
	- This will also make adding the remaining consoles easier.
10. Relative paths are now used instead of full paths in the log files and console output.
11. Various bug fixes relating to the modularization of the application discovered during SNES cartridge dumping.


<br/><br/>
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
14. Adjusted step 1 in the cart detection to only treat `SRAM` as present when a numeric size is parsed (ex, “SRAM Size: 32K” or “256 kilobits” → 32KB). 
	- This fixed false positives on non-battery games.
15. Corrected `map_mode_desc` so common values display “`LoROM FastROM”/“HiROM FastROM`” instead of misleading “`+ EXHIROMSA1`”.
16. After a game cartridge is dumped, made input faster to keep dumping cartridges.
	- Pressing [Enter] will default to `No` for the following:
		- "Would you like to access the RetroRGB.com article on cleaning best practices? (y/n)”
		- “Proceed with another attempt? (An incremental version will be made.) (y/n)”
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


<br/><br/>
**10/26/2025 `(host/archive/inlretro-interface-10f.ps1)`**
1. Corrected issues with `v2proto_hirom.lua` where:
	 - The validation was checking if `rom_size` and `sram_size` were "truthy", but 0 is falsy in LUA.
	 - The cartridge `Plok` returned rom_type: 5, but this wasn't defined in the lookup table. Added `[0x05] = "ROM, Save RAM and DSP1 chip"` to the hardware_type table.
	 - The script was using the user-specified mapping `(-m hirom)` even when it detected a different mapping from the cartridge header.
	 - Added error handling for division by zero. The `dump_rom` function could fail if `KB_per_bank` is nil.
	 - Added error handling for division by zero. The `dump_ram` function could fail if `KB_per_bank` is nil.
2. Addressed issues within the `v2proto_hirom.lua`, such as:
	- The TODO comment lists several missing hardware types that should be added (originally lines 26, 27, 32, 35).
	- There was a reference to `flashfile` that's not defined (originally line 993).
	- There was a reference to `verifyfile` that's not defined (originally line 1010).
	- The variables `sram_table` and `exp_ram_table` are used but not declared (originally lines 897-898).
3. Within the interface file, the parameter `-m` is not passed anymore since the LUA script seems to (at least with my testing base) be able to determine correctly what is a `HiROM` and `LoROM` (based on a hardware address check).
4. Automatic SRAM detection performing well now to see what parameters need to be used when dumping the cartridge and save data.
5. Created a function `ConvertTo-SafeFileName` that will check for input of characters invalid in Windows file names. 
	- Converts `< > : " / \ |` to ` - `.
	- Strips out `? *`.
6. Error catching now terminates the program with the error message displayed on the screen.
7. Formatting clean up on UI elements.
8. Improved output text on Powershell > 7 check.
9. Formatting in log files and script output for files over 1,000kb to have commas where needed to make reading the sizes easier.
10. Fixed issue where `Stunt Racer FX` wasn't detecting SRAM during cartridge detection.
11. Cleaned up some formatting and wording issues with the generated log file.
12. Added `0x04` to the `sram_size_tbl` so that the SRAM for `Donkey Kong Country` could be correctly dumped.
13. Made the cartridge detection output more user friendly and understandable to read.
	- It is also now logged in the appropriate logfile for future reference.
14. ~~When required data files are missing, the default GitHub page opens to redownload them.~~
15. Cartridge detection uses hardware mappers from `v2proto_hirom.lua` instead of hoping the correct filename is given.
16. A counter was placed on the detection method screen to indicate if the program is still responsive.
17. Added additional hardware detection types, allowing for more lenient validation for third-party cartridges.
	- [0x20] = "ROM Only (Third-party)"
	- [0x21] = "ROM and RAM (Third-party)"
	- [0x30] = "ROM Only (Majesco)"
	- [0x31] = "ROM and RAM (Majesco)"
18. Enhanced ROM name-based validation will accept headers based on ROM name even if ROM type is unknown (during detection).
	- Fallback mechanism that was added to help detect cartridges with non-standard or corrupted headers.
	- The enhanced validation allows the dumper to work with a much wider range of cartridges, including:
		- Majesco PCBs (like The Jungle Book)
		- Bootleg cartridges (although not tested, just in theory).
		- Reproduction cartridges (although not tested, just in theory).
		- Cartridges with slightly corrupted headers (although possible to be cleaned and work correctly).
19. Added nil check for `hw_type_str` before using `string.find()`.
20. Fixed session timer which now correctly tracks total time from detection start to completion.
21. Added detection for `SRAM Size: [X] kilobits` and conversion to KB (ex. `64 kilobits → 8KB`). 
	- This corrected a large amount of carts having SRAM dumping issues.
22. Set `hasSRAM = true` and default `sramSizeKB to 8KB` when `Save RAM` is found in Hardware Type.
23. Added default ROM bank `0x00` detection, assuming it's not discovered elsewhere.
24. Added default RAM bank `0x70` detection, assuming it's not discovered elsewhere.
25. Corrected to where `SA-1` games dump `BW-RAM` instead of standard SRAM.


<br/><br/>
**10/15/2025 `(host/archive/inlretro-interface-08f.ps1)`**
1. Added logging feature.
	- Logs are now saved in the `logs` directory with the name `interface-cmds-[datestamp].txt`.
	- The name of the log file is shown in the program header now but will not generate until a cartridge dump is processed.
	- The cartridge path, SRAM path, file size, and the command used to generate the file are all logged.
	- Redumps are also logged.
2. Lots of code optimization.
3. Renamed the program header to reflect the Github name.
	- `INL Retro Dumper Interface` is now shown as `INL Retro Interface`.
	- Added coloring to the ASCII logo.
4. The check for PowerShell 7.x now can download and install from within previous versions of PowerShell.
5. PowerShell window now automatically resizes to the maximum vertical height and moves to the top-left of the active monitor, making all content easier to view at once.
6. Will begin working on `Super Nintendo Entertainment System` section next.
	- Outside of the No-Intro comparison, I don't believe any other Quality of Life changes are needed at this time. Always open to suggestions.


<br/><br/>
**10/12/2025 `(host/archive/inlretro-interface-08c.ps1)`**
1. Optimized the section for dumping `Nintendo Entertainment System` and `Famicom` system cartridges. Since they both use the same mappers, but will save in seperate folders based on the selected console.
2. Cleaned up the `Super Nintendo Entertainment System` dumper section to match more of the `Nintendo Entertainment System` section. This section has not been tested yet and will more than likely have additional modifications.
3. Cleaned up the code for the browser open/refresh whenever opening `NEScartDB`.
4. Made it easier if someone wants to change the timing for the browser window to open and refresh back to the UI.
5. Made a change to where only a console folder that doesn't exist is created whenever that console is referenced.
6. Implemented a (hopefully) graceful exit in the event of a crash (ie. USB device hangs).
7. Some display optimization and tweaking (mainly formatting).
8. Removed the need for the supporting file `host/data/config.json`.
9. Added the option to redump the same cartridge again using the same parameters without needing to reenter the needed cartridge information. File names will be incremental, example:
	- `Adventure Island.nes`
	- `Adventure Island-dump1.nes`
	- `Adventure Island-dump2.nes`
10. Added an option to exit the script at the end a cartridge dump or at the main menu.
11. Give the option to quickly access `RetroRGB`'s cartridge cleaning article (https://www.retrorgb.com/cleangames.html) during the redumping period.
12. Added a session counter to monitor how many cartridge dumps have been performed. Count does not persist.


<br/><br/>
**09/28/2025 `(host/archive/inlretro-interface-07.ps1)`**
1. Fixed several instances in `host/scripts/app/dump.lua` where `op_buffer` references were not properly namespaced as `dict.op_buffer`, which would otherwise result in runtime errors when accessing buffer operation constants.
2. Successfully dumped an additional Nintendo Entertainment System cartridge, `Kung Fu`, without requiring mapper modifications.
3. Updated interface UI and extended supported file handling to enable dumping of `Nintendo Famicom` cartridges.
4. Modified `host/scripts/nes/nrom.lua` to correctly detect and handle the `NROM-256` mapper, enabling successful dumps of `Son Son` and `Spelunker`.
5. Began development of a `NAMCOT-3415` mapper, referencing available documentation from `DxROM` and `MMC1` variants. Functionality remains incomplete; see NES Mapper changelog (`changelog-nes-mappers.md`) for additional details.
6. An inital run through of all the Nintendo Famicom Family Computer Games that I own were completed.
	- Initally five games dumped without issue.
	- One cartridge uses a mapper not programmed with INL-Retro - `NAMCOT-3415`.
	- Two worked after existing mapper modifications to the `NROM` mapper was done.
7. A second run of dumping Nintendo Famicom Carts yielded the following results:
	- Seven cartridges dumped without issue.
	- One cartridge continues to be an issue.
	- One Nintendo Entertainment System cartridge using the `NROM` mapper was also tested and working (checking on 128 and 256 detection).


<br/><br/>
**09/25/2025 `(host/archive/inlretro-interface-06d.ps1)`**
1. NES Database opens to a search page based on the name of the cartridge that's entered.
2. Note on ANROM cartridges in the powershell script.
3. Language cleanup in the powershell script.
4. `host/scripts/nes/MMC1.lua` was modified due to `Final Fantasy` not running after being dumped.
5. `host/scripts/nes/cnrom.lua` was modified due to `Adventure Island` showing grabbled text.
6. ~~NES Database site with inputted Game Title name will appear in Microsoft Edge for faster access.~~
7. `host/scripts/nes/mhrom.lua` is a new mapper which was made for the `Super Mario Bros. & Duck Hunt` multicart.
8. `inlretro2.lua` mapping was modified to point to the new mapper for both MHROM and GxROMs.
9. Interface UI was also given an update for correct mapping selection.
10. Interface UI has a festive ASCII art header now!
11. Interface UI flow and presentation was cleaned up as cart dumping progressed.
12. Moved referenced assets to external JSON files, allows easier modifications of assets when needed.
13. `host/scripts/nes/MMC3.lua` was modified due to incompatibilities with dumping Mega Man 3 which. Additional changes were needed after `Mega Man 3` was working but `Astyanax` (which previously worked) was no longer functional.
14. NES database site now will open regardless of end user's default browser and will refocus on the UI without error.
15. `host/scripts/nes/unrom.lua` was modified due to `Ducktales` not properly dumping. This fix caused Mega Man 3 and Castlevania not to work. Enabling automatic bank table detection instead of using a hardcoded address fixed the issue for the cartridges. Also tested were `Top Gun` and `Mega Man`.
16. `host/scripts/nes/mmc1.lua` was modified due to `Dragon Warrior` not properly dumping. Changing back to simple bank switching seems to have fixed the issue.
17. An inital run through of all the Nintendo Entertainment Games that I own were completed during the mapper modification phase. Afterwards, another dump of all the cartridges again were performed grouping them by mapper. This resulted in 2 mappers needing to be modified again `UNROM` and `MMC1`. The end result being that `75 games were successful` and `1 was never able to be dumped`.


<br/><br/>
**09/15/2025 `(host/archive/inlretro-interface-05.ps1)`**
1. Script cleanup and optimation around calling the inlretro executable.
2. Addressed wrong NES Mapper references.
3. Beginning personal cart dump of NES carts and will correct issues as they might appear.
4. Script name changed to match repository name.


<br/><br/>
**09/14/2025 `(host/archive/INL_Retro_Interface-03.ps1)`**
1. Script cleanup and optimation around calling the inlretro executable.
2. Color coding certain items to be easier to view.


<br/><br/>
**09/13/2025 `(host/archive/INL_Retro_Interface.ps1)`**
1. Command file was converted to a PowerShell script.
2. Code cleanup and repeated tasks converted to functions.
3. NES fine tuning and testing has begun.
    - All other platforms ignored for the time being.


<br/><br/>
**09/12/2025**
- Project resurrected!


<br/><br/>
**03/11/2020**
- Project abandoned.


<br/><br/>
**08/18/2019 `(host/archive/interface-04.cmd)`** 
1. NES cartridges better.
2. SNES compatibility began, somewhat worked.


<br/><br/>
**05/07/2019 `(host/archive/interface-02.cmd)`**
1. Initial release as a command file.
2. NES script was somewhat working.

====

### To Do:

2. SNES Functionality
3. Nintendo 64 Functionality
4. Gameboy Functionality
5. Sega Genesis Functionality
6. No-Intro dat comparison, file name clean up
7. Write SRAM saves back to carts.
