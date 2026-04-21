### Commited Changes

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