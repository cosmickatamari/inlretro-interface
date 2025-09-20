2025 () -
- NES Database opens to a search page based on the name of the cartridge that's entered.
- Note on ANROM cartridges in the powershell script.
- Language cleanup in the powershell script.
- hosts/scripts/nes/MMC1.lua was modified due to Final Fantasy (USA) not running after being dumped.
-   Reset (0x80) > delay > shift in 5 bits (LSB-first). Original script was doing this too fast.
-   Used control register 0x0E to put MMC1 in 16 KB switchable at $8000 / fixed last bank at $C000.
- hosts/scripts/nes/cnrom.lua was modificed due to Adventure Island (USA) showing grabbled text.
-   bus-conflict problem during CHR bank selects
-   dumper was writing a bank number to changing addresses, causing the wrong CHR bank to be hatched.
- NES Database site with inputted Game Title name will appear in Edge for faster access.
- hosts/scripts/nes/mhrom.lua is a new mapper which was made for the Super Mario Bros. + Duck Hunt multicart.
-   MHROM and GXROM are actually the same mapper (iNES mapper 66) - they're just different names for the same hardware.
-   Another fork of the project here has a modification to the GxROM mapper - https://gitlab.com/kevinms/INL-retro-progdump/-/blob/d936b8eac92c3206f13301a7df1ac5dd36699938/host/scripts/nes/gxrom.lua
-   Had to make some changes based off of it in order to get a functional dump of the rom.
-   inlretro2.lua mapping was modified to point to the new mapper for both MHROM and GxROMs.
-   Interface UI was also given an update for correct mapping selection.

2025/09/15 (inlretro-interface-05.ps1) -
- Script cleanup and optimation around calling the inlretro executable.
- Addressed wrong NES Mapper references.
- Beginning personal cart dump of NES carts and will correct issues as they might appear.
- Script name changed to match repository name.

2025/09/14 (archive/INL_Retro_Interface-03.ps1) -
- Script cleanup and optimation around calling the inlretro executable.
- Color coding certain items to be easier to view.

2025/09/13 (archive/INL_Retro_Interface.ps1) - 
- Command file was converted to a PowerShell script.
- Code cleanup and repeated tasks converted to functions.
- NES fine tuning and testing has begun.
- All other platforms ignored for the time being.

2025/09/12 - 
- Project resurrected.

2020/03/11 - 
- Project abandoned.

2019/08/18 (archive/interface.cmd) -
- Initial release as a command file. NES and SNES files somewhat worked.

====

Wish List:
Move Mapper and Console Assets to a seperate file
SNES Functionality
Nintendo 64 Functionality
Gameboy Functionality
Sega Genesis Functionality
No-Intro dat comparison, file name clean up
Active counter during session
Stager for updated files in existing installs
