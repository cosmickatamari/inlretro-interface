### Commited Changes
**10/26/2025 `(host/inlretro-interface-10f.ps1)`**
1. Corrected issues with `v2proto_hirom.lua` where:
	 - The validation was checking if rom_size and sram_size were "truthy", but 0 is falsy in LUA.
	 - The cartridge `Plok` returned rom_type: 5, but this wasn't defined in the lookup table. Added [0x05] = "ROM, Save RAM and DSP1 chip" to the hardware_type table.
	 - The script was using the user-specified mapping (-m hirom) even when it detected a different mapping from the cartridge header.
	 - Added error handling for division by zero. The `dump_rom` function could fail if `KB_per_bank` is nil.
	 - Added error handling for division by zero. The `dump_ram` function could fail if `KB_per_bank` is nil.
2. Addressed issues within the `v2proto_hirom.lua`, such as:
	- The TODO comment lists several missing hardware types that should be added (originally lines 26, 27, 32, 35).
	- There was a reference to `flashfile` that's not defined (originally line 993).
	- There was a reference to `verifyfile` that's not defined (originally line 1010).
	- The variables `sram_table` and `exp_ram_table` are used but not declared (originally lines 897-898).
3. Within the interface file, the parameter `-m` is not passed anymore since the LUA script seems to (at least with my testing base) be able to determine correctly what is a HIROM and LOROM (based on a hardware address check).
4. Automatic SRAM detection performed to see if the parameter even needs to be used when dumping the cartridge.
5. Included a function `ConvertTo-SafeFileName` that will check for input of characters invalid in Windows file names. 
	- Converts `< > : " / \ |` to ` - `.
	- Strips out `? *`.
6. Error catching now terminates the program with the error message displayed on the screen.
7. Formatting clean up on UI elements.
8. Improved output text on Powershell > 7 check.
9. Formatting in log files and script output for files over 1,000kb to have commas where needed to make reading the sizes easier.
10. Fixed issue where `Stunt Racer FX` wasn't detecting SRAM during cartridge detection.
	- It looks like the SRAM is dumping (maybe); however I'm unable to get Mesen to reference the save data. Will need more testing.
11. Cleaned up some formatting and wording issues with the generated log file.
12. Added `0x04` to the `sram_size_tbl` so that the SRAM for `Donkey Kong Country` could be correctly dumped.
13. Made the cartridge detection output more user friendly and understandable to read.
	- It is also now logged in the appropriate logfile for future reference.
14. When required data files are missing, the default GitHub page opens to redownload them.
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
21. Added detection for `SRAM Size: X kilobits` and conversion to KB (ex. `64 kilobits → 8KB`). This corrected a large amount of carts having SRAM dumping issues.
22. Set `hasSRAM = true` and default `sramSizeKB to 8KB` when "Save RAM" is found in Hardware Type.
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