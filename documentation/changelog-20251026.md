### Commited Changes

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
