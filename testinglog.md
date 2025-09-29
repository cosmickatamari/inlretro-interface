### Nintendo Entertainment System:

| Name | Mapper | Battery | Notes |
| -- | -- | -- | -- |
| Abadox: The Deadly Inner War | MMC1 | None | None |
| Adventure Island | CNROM | None | Required original mapper modifications. |
| Adventure Island II | MMC3 | None | None |
| Adventures of Lolo | MMC1 | None | None |
| Arkista's Key | CNROM | None | None |
| Astyanax | MMC3 | None | Required original mapper modifications. |
| Balloon Fight | NROM | None | None |
| Battletoads | AOROM (using BNROM) | None | None |
| ~~Battle of Olympus, The~~ | MMC1 | None | [Unable to dump cartridge.](#battle-of-olympus-the) |
| Blaster Master | MMC1 | None | None |
| Bubble Bobble | MMC1 | None | None |
| Bucky O'Hare | MMC3 | None | None |
| Bump 'n' Jump | CNROM | None | None |
| CastleQuest | CNROM | None | None |
| Castlevania | UNROM | None | Required original mapper modifications. |
| Castlevania II: Simon's Quest | MMC1 | None | None |
| Castlevania III: Dracula's Curse | MMC5 | None | None |
| [Disney's] Chip 'n Dale Rescue Rangers | MMC1 | None | None |
| Crystalis | MMC3 | Backs Up | None |
| [Disney's] Darkwing Duck | MMC1 | None | None |
| Dig Dug II: Trouble in Paradise | NROM | None | None |
| Digger T. Rock: The Legend of the Lost City | AOROM (using BNROM) | None | None |
| Donkey Kong Classics | CNROM | None | Multicart for `Donkey Kong` and `Donkey Kong Jr.` |
| Dr. Mario | MMC1 | None | None |
| Dragon Warrior | MMC1 | Backs Up | Required original mapper modifications. |
| [Disney's] DuckTales | UNROM | None | Required original mapper modifications. |
| Excitebike | NROM | None | None |
| Faxanadu | MMC1 | None | None |
| Felix the Cat | MMC3 | None | None |
| Final Fantasy | MMC1 | Backs Up | Required original mapper modifications. |
| Gauntlet II (NES Version) | MMC3 | None | None |
| Ice Climber | NROM | None | None |
| Journey to Silius | MMC1 | None | None |
| Kirby's Adventure | MMC3 | Backs Up | None |
| Legacy of the Wizard | MMC3 | None | None |
| Legend of Zelda, The | MMC1 | Backs Up | None |
| Little Nemo: The Dream Master | MMC3 | None | None |
| Marble Madness | ANROM (using BNROM) | None | BNROM mapper works for ANROM cartridges. |
| Mario Bros. | NROM | None | None |
| Mega Man | UNROM | None | None |
| Mega Man 2 | MMC1 | None | None |
| Mega Man 3 | MMC3 | None | Required original mapper modifications |
| Mega Man 4 | MMC3 | None | None |
| Mega Man 5 | MMC3 | None | None |
| Mega Man 6 | MMC3 | None | None |
| Metroid | MMC1 | None | None |
| Mickey Mousecapade | CNROM | None | None |
| NES Open Tournament Golf | MMC1 | Backs Up | None |
| Paperboy | CNROM | None | None |
| Platoon | MMC1 | None | None |
| R.C. Pro-AM | MMC1 | None | None |
| Rad Racer | MMC1 | None | None |
| Rad Racer II | MMC3 | None | None |
| Rampage | MMC3 | None | None |
| Snake Rattle n Roll | MMC1 | None | None |
| Solor Jetman: Hunt for the Golden Warpship | AOROM (using BNROM) | None | None |
| Solomon's Key | CNROM | None | None |
| Solstice: The Quest for the Staff of Demnos | ANROM (using BNROM) | None | BNROM mapper works for ANROM cartridges. |
| StarTropics | MM6 (using MMC3) | Backs Up | None |
| Super Mario Bros. & Duck Hunt | MHROM (using GxROM | None | Mutlticart for `Super Mario Bros.` and `Duck Hunt` |
| Super Mario Bros. 2 | MMC3 | None | None |
| Super Mario Bros. 3 | MMC3 | None | Required original mapper modifications. |
| [Disney's] TaleSpin | MMC1 | None | None |
| Teenage Mutant Ninja Turtles | MMC1 | None | None |
| Tetris | MMC1 | None | None |
| Tetris 2 | MMC3 | None | None |
| Tiny Toon Adventures | MMC3 | None | None |
| Top Gun | UNROM | None | None |
| Ultima Exodus | MMC1 | None | None |
| Willow | MMC1 | None | None |
| Wizards & Warriors | ANROM (using BNROM) | None | BNROM mapper works for ANROM cartridges. |
| Zelda II: The Adventures of Link | MMC1 | Backs Up | None |
| Zoda's Revenge: StarTropics II | MM6 (using MMC3) | Backs Up | None |


<br/><br/>
### Nintendo Famicom (Family Computer)
| Name | Mapper | Battery | Notes |
| -- | -- | -- | -- |
|Final Fantasy | MMC1 | Backs Up | Cartridge was translated using [Voultar's Translation Service](https://voultar.com/index.php?route=product/product&path=60&product_id=82). |
|Final Fantasy | MMC1 | Backs Up | Cartridge was translated using [Voultar's Translation Service](https://voultar.com/index.php?route=product/product&path=60&product_id=82). |
|Final Fantasy | MMC3 | Backs Up | Cartridge was translated using [Voultar's Translation Service](https://voultar.com/index.php?route=product/product&path=60&product_id=82). |
| ~~Mappy-Land~~ | NAMCOT-3415 | None | [Unable to dump cartridge.](#mappy-land-famicom) |
| Pooyan | NROM | None | None |
| Son Son | NROM-256 | None | Required original mapper NROM modifications. |
| Spelunker | NROM-256 | None | Required original mapper NROM modifications. |
| Terra Cresta | UNROM | None | None |


<br/><br/> 
> [!IMPORTANT]
> I was unable to get the following cartridges to correctly dump their contents.

### Battle of Olympus, The
Regardless of method tried, the mapper will only read `FF` for all data banks. With the exception of the header, none of the actual data is being written to the ROM file.

Mapper Modifications Attempted:
- Standard MMC1 initialization (original working approach). 
- Mode 2/3 approaches (different PRG banking modes).
- Direct memory access (bypassing mapper functions)
- MMC3-style approach (mimicking MMC3 game detection)
- No initialization (reading immediately after CHR-ROM ID)
- [Kevtris](http://kevtris.org/mappers/mmc1/index.html) approach (based on Kevtris documentation)
- [emudev](https://www.nesdev.org/wiki/MMC1) approach (based on emudev documentation)
- [Mario's Right Nut](https://mariosrightnut.com/nintendo/mmc1/) approach (based on assembly tutorial)
- [Mouse Bite Labs](https://mousebitelabs.com/2021/01/27/nes-reproduction-board-guide-mmc1/) approach (based on reproduction board guide) 
- Standard MMC1 with proper 5-write sequences (exact working game init)
- Real NES power-on sequence (mimicking actual NES boot)

### Mappy-Land (Famicom)
The `NAMCOT-3415` mapper is not officially documented, nor is `DxROM`, which online sources suggest as its default mapping configuration. A provisional implementation of the mapper has been placed in `hosts/scripts/nes/namcot3415.lua` for further review and refinement. The objective is for another developer to examine the code, interpret its behavior, and potentially achieve functional support. Currently, only one other title, `Family Circuit`, utilizes this mapper.

What was tested:
- Mappers Tested:
	- Mapper 0 (NROM) - Multiple configurations
	- Mapper 1 (MMC1) - Standard approach
	- Mapper 4 (MMC3) - With MMC3-style bank switching
	- Mapper 206 (NAMCOT-3415) - Original mapper name

- ROM Size Combinations:
	- 128KB PRG + 32KB CHR (161KB total)

- Mirroring Options:
	- Horizontal mirroring (worked for Son Son)

- PRG ROM Reading Methods:
	- Simple approach - 4 reads of 32KB each
	- Smaller reads - 8 reads of 16KB each
	- MMC3-style bank switching - 16 banks of 8KB each
	- NAMCOT-3415-style bank switching - Various bank configurations

- CHR ROM Reading Methods:
	- Standard reading - 4 reads of 8KB each
	- Multiple-pass reading - 3 passes with majority voting (worked for Spelunker)
	- Direct byte-by-byte reading - Manual reading of each byte
	- 8KB range (0x0000-0x1FFF)
	- 32KB range (0x0000-0x7FFF)

- Results:
	- All combinations resulted in: Green screens, crashes, garbled graphics, or no response
	- Best outcome: Got sound and some graphics but still garbled against MMC3 mapper