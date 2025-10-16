# inlretro-interface

## Overview:
This project provides an interactive PowerShell interface for dumping retro game cartridges using the INL Retro Dumper hardware. The hardware supports a wide range of 8-bit and 16-bit cartridge-based systems, and this software aims to make the dumping process straightforward, reliable, and easy to use.

<br/><br/>
## About the Modifications:
This project contains modified versions of the original support files used by the INL Retro Dumper software. These changes were necessary to enable accurate data extraction from cartridges that did not function correctly with the stock configuration. All modifications are fully documented and serve as drop-in replacements for the original sources. By extending the original software, this project improves compatibility and reliability for specific cartridges. If you fork or adapt this project for your own development, please give appropriate credit.

Written and tested using:
* Windows 11 24H2
* PowerShell 7.5.3
* INL Retro firmware 2.3.x

<br/><br/>
## Cartridge Testing & Validation:
While not every commercially released cartridge is available for testing, a comprehensive list of verified titles is included for reference. Each tested cartridge undergoes at least two validation passes (assuming the initial dump completes successfully):
- First Pass: Performed during the initial data write.
- Second Pass: Conducted after all cartridges in the collection for a given platform have been processed.

The purpose of this second validation cycle is to verify overall stability and confirm that no further adjustments to mapper logic or support files are required.

<br/><br/>
## Current Progress:
| Console | Success | Failure | Success Rate | Last Updated |
| -- | -- | -- | -- | -- |
| Nintendo Entertainment System | 76 | 1 | 98.70% | 9/26/2025 |
| Nintendo Famicom (Family Computer) | 7 | 1 | 87.50% | 9/29/2025 |
| Super Nintendo Entertainment System | | | | |
| Super Famicom | | | | |
| Nintendo 64 | | | | |
| Sega Genesis | | | | |
| Nintendo Gameboy | | | | |
| Nintendo Gameboy Advance | | | | |

<br/><br/>
## Installation:
1. From the Releases section, download the `Original Program` package and extract its contents.
2. Connect the INL Retro Dumper to an available USB port. For testing purposes, a USB 2.0 port was intentionally used to reduce transfer speed and aid in stability verification.
3. Navigate to the `WindowsDriverPackage\` directory and execute `dpinst64.exe` to install the required drivers.
4. From the Releases section, download the `Current Program` package with the most recent timestamp and extract its contents into the same directory where the `Original Program` was extracted. When prompted, **overwrite** all existing files.
5. Launch the script `inlretro-interface.ps1` located in the `host\` folder with the most recent date to begin usage.

<br/><br/>
## Links (non affiliated):
- Cart dumper purchase link: https://www.infiniteneslives.com/inlretro.php
- Original Author's Project: https://gitlab.com/InfiniteNesLives/INL-retro-progdump
- 3D printed case purchase link: (need to upload)
- 3D printed case can self-printed link: https://www.printables.com/model/2808-inlretro-dumper-programmer-case-v2
- RetroRGB.com :: Cartridge Cleaning Methods: https://www.retrorgb.com/cleangames.html

<br/><br/>
## Disclaimer:
- This project is not affiliated with the original author (Infinite NES Lives) or any commercial entity.
- The software and modifications are intended solely for personal backup, preservation, and research purposes.
- Use responsibly and ensure that you own any cartridges you dump; the repository does not provide copyrighted ROMs.
- **No warranty is provided; use at your own risk.**
