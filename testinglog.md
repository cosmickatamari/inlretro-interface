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
| Kid Icarus | MMC1 | None | None |
| Kung Fu | NROM | None | None |
| Kirby's Adventure | MMC3 | Backs Up | None |
| Legacy of the Wizard | MMC3 | None | None |
| Legend of Zelda, The | MMC1 | Backs Up | None |
| Little Nemo: The Dream Master | MMC3 | None | None |
| Life Force | UNROM | None | None |
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
| Wario's Woods | MMC3 | Backed Up | None |
| Willow | MMC1 | None | None |
| Wizards & Warriors | ANROM (using BNROM) | None | BNROM mapper works for ANROM cartridges. |
| Zelda II: The Adventures of Link | MMC1 | Backs Up | None |
| Zoda's Revenge: StarTropics II | MM6 (using MMC3) | Backs Up | None |

<br/><br/> 
> [!IMPORTANT]
> I was unable to get the following cartridges to correctly dump their contents.

### Battle of Olympus, The
Regardless of method tried, the mapper will only read `FF` for all data banks. With the exception of the header, none of the actual data is being written to the ROM file.

Modifications Attempted:
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
