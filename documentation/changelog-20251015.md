### Commited Changes

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
