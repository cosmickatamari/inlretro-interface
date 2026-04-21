### Commited Changes

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
