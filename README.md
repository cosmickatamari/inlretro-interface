# inlretro-interface

PowerShell interface for the INL-Retro Dumper / Programmer.
https://www.infiniteneslives.com/inlretro.php

Written and tested using:

* Windows 11 24H2
* PowerShell 7.5.3
* INL Retro firmware 2.3.x

<br/>

The files in this repository serve as modified replacements for the original sources. These modifications were required to enable proper data extraction from specific cartridges. While I do not possess every commercially released cartridge, a comprehensive list of tested titles is included for reference. Each cartridge undergoes a minimum of two validation passes (provided an initial dump is successful). 
1. The first pass occurs during the initial data write.
2. The second occurs after all cartridges in my collection for a given platform have been processed.
The objective of this second validation cycle is to confirm stability and ensure that no further adjustments to the mapper logic or related support files are necessary.

<br/>

## Current Progress:
| Console | Success | Failure | Success Rate | Last Updated |
| -- | -- | -- | -- | -- |
| Nintendo Entertainment System | 75 | 1 | 99% | 9/25/2025 |
| Famicom | | | | |
| Super Nintendo Entertainment System | | | | |
| Super Famicom | | | | |
| Nintendo 64 | | | | |
| Sega Genesis / Mega Drive | | | | |
| Gameboy | | | | |
| Gameboy Advance | | | | |

<br/>

## Installation:
1. From the Releases section, download the `Original Program` package and extract its contents.
2. Connect the INL Retro Dumper to an available USB port. For testing purposes, a USB 2.0 port was intentionally used to reduce transfer speed and aid in stability verification.
3. Navigate to the `WindowsDriverPackage\` directory and execute `dpinst64.exe` to install the required drivers.
4. From the Releases section, download the `Current Program` package with the most recent timestamp and extract its contents into the same directory where the `Original Program` was extracted. When prompted, **overwrite** all existing files.
5. Launch the script `inlretro-interface.ps1` located in the `host\` folder with the most recent date to begin usage.
