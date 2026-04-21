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
