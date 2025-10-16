### Commited Changes
**10/15/2025 `(host/inlretro-interface-08f.ps1)`**
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