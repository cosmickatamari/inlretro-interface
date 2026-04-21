### Commited Changes

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
