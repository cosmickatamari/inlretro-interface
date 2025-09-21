### Commited Changes
**2025 () -**
1. NES Database opens to a search page based on the name of the cartridge that's entered.
2. Note on ANROM cartridges in the powershell script.
3. Language cleanup in the powershell script.
4. `hosts/scripts/nes/MMC1.lua` was modified due to `Final Fantasy (USA)` not running after being dumped.
    - Reset (0x80) > delay > shift in 5 bits (LSB-first). Original script was doing this too fast.
    - Used control register 0x0E to put MMC1 in 16 KB switchable at $8000 / fixed last bank at $C000.
5. `hosts/scripts/nes/cnrom.lua` was modified due to `Adventure Island (USA)` showing grabbled text.
    - Bus conflict problem during CHR bank selects
    - Dumper was writing a bank number to changing addresses, causing the wrong CHR bank to be hatched.
6. NES Database site with inputted Game Title name will appear in Microsoft Edge for faster access.
    - Will eventually change it to the default browser for other people.
7. `hosts/scripts/nes/mhrom.lua` is a new mapper which was made for the `Super Mario Bros. & Duck Hunt (USA)` multicart.
    - MHROM and GXROM are essentially the same mapper (iNES mapper 66) - they're just different names from two different vendors for the same hardware.
    - Another fork of the project has a modification to the GxROM mapper - https://gitlab.com/kevinms/INL-retro-progdump/-/blob/d936b8eac92c3206f13301a7df1ac5dd36699938/host/scripts/nes/gxrom.lua
    - From the above GxROM mapper, made some changes based off of it in order to get a functional dump of the rom. Mainly issue with bank switching.
    - Changes were made to the MHROM mapper, leaving the original GTROM mapper unmodified.
8. `inlretro2.lua` mapping was modified to point to the new mapper for both MHROM and GxROMs.
9. Interface UI was also given an update for correct mapping selection.
10. Interface UI has a festive ASCII art header now!
11. Interface UI flow and presentation was cleaned up as cart dumping progressed.
12. Moved referenced assets to external JSON files, allows easier modifications of assets when needed.

<br/><br/>
**09/15/2025 `(inlretro-interface-05.ps1)`**
1. Script cleanup and optimation around calling the inlretro executable.
2. Addressed wrong NES Mapper references.
3. Beginning personal cart dump of NES carts and will correct issues as they might appear.
4. Script name changed to match repository name.

<br/><br/>
**09/14/2025 `(archive/INL_Retro_Interface-03.ps1)`**
1. Script cleanup and optimation around calling the inlretro executable.
2. Color coding certain items to be easier to view.

<br/><br/>
**09/13/2025 `(archive/INL_Retro_Interface.ps1)`**
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
**08/18/2019 `(archive/interface-04.cmd)`** 
1. NES cartridges better.
2. SNES compatibility began, somewhat worked.

<br/><br/>
**05/07/2019 `(archive/interface-02.cmd)`**
1. Initial release as a command file.
2. NES script was somewhat working.

====

### To Do:
1. Move Mapper and Console Assets to a seperate file
2. SNES Functionality
3. Nintendo 64 Functionality
4. Gameboy Functionality
5. Sega Genesis Functionality
6. No-Intro dat comparison, file name clean up
7. Active counter during session
8. Stager for updated files in existing installs
9. Change the browser opening for NES database from Edge to the end user's default browser.
