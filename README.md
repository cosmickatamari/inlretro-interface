# inlretro-interface

## Overview:
This project provides an interactive PowerShell interface for dumping retro game cartridges using the INL Retro Dumper hardware. This software is meant as a drop in for the existing project, originally created by InfiniteNesLives and will require overwriting files from this project ontop of his. All files are provided in the releases section. All modifications are fully documented.

<br/>
The hardware supports a wide range of cartridge-based systems, this software aims to make the dumping process more straightforward, reliable, and easy to use.

<br/><br/>
## About Modifications:
This project contains both modified versions of the original support files as well as new files created during developement. These changes were necessary to enable more accurate data extraction from cartridges that did not function correctly with the stock configuration and/or mappers.
- If you have an existing installation of the original software, I would recommend applying this project to a copy of that installation.
- If you fork or adapt this project for your own development, please give appropriate credit. 

<br/><br/>
Written and tested using:
* Windows 11 25H2
* PowerShell 7.5.3
* INL Retro firmware 2.3.3

<br/><br/>
## Cartridge Testing & Validation:
While I do not own or have access to every commercially released cartridge for testing, a comprehensive list of self tested titles are included for reference in the [testing log](documentation/testinglog.md). Each tested cartridge undergoes at least two validation passes (assuming the initial dump completes successfully):
- First Pass: Performed during the initial data write.
	- If the first pass fails, troubleshooting is performed to see what required changes are needed.
- Second Pass: Conducted after all cartridges in the collection for a given platform have been processed.
	- This is considered an additional release candidate phase where I would feel comfortable with releasing to the public for testing.
- Third Pass: This is required should there be additional issues during the second pass or new issues from previously working cartridges are now present from resolving issues with other cartridges from the same console.
	- This process will continue until either all known cartridges for a console work in one session or if there are known issues for a cartridge preventing it from being correctly dumped. 

<br/><br/>
## Game ROM Progression:
| Console | Success | Failure | Success Rate | Last Updated |
| -- | -- | -- | -- | -- |
| Nintendo Entertainment System | 76 | 1 | 98.70% | 9/26/2025 |
| Nintendo Famicom (Family Computer) | 7 | 1 | 87.50% | 9/29/2025 |
| Super Nintendo Entertainment System | 108 | 5 | 95.58% | 12/17/2025 |
| Super Famicom | 0 | 1 | 0.00% | 11/06/2025 |

<br/><br/>
## Game Save Progression:
| Console | Success | Failure | Success Rate | Last Updated |
| -- | -- | -- | -- | -- |
| Nintendo Entertainment System | 9 | 0 | 100% | 9/26/2025 |
| Nintendo Famicom (Family Computer) | 3 | 0 | 100% | 9/29/2025 |
| Super Nintendo Entertainment System | 36 | 8 | 81.82% | 12/17/2025 |
| Super Famicom | 0 | 1 | 0.00% | 11/06/2025 |

<br/><br/>
## Installation:
1. From the Releases section, download the `Original Program` package and extract its contents.
2. Connect the INL Retro Dumper to an available USB port. For testing purposes, a USB 2.0 port was intentionally used to reduce transfer speed and aid in stability verification.
3. Navigate to the `.\WindowsDriverPackage` directory and execute (as administrator) `dpinst64.exe` to install the required drivers.
4. From the Releases section, download the `Current Program` package with the most recent timestamp and extract its contents into the same directory where the `Original Program` was extracted. When prompted, **overwrite** all existing files.
5. Launch the script `inlretro-interface[xx].ps1` located in the `.\host` folder with the most recent date to begin usage.

<br/><br/>
## Links (non affiliated):
- Cart dumper purchase link: https://www.infiniteneslives.com/inlretro.php
- Original Author's Project: https://gitlab.com/InfiniteNesLives/INL-retro-progdump
- 3D printed case purchase link: ()
- 3D printed case STL (for self-printing) link: https://www.printables.com/model/2808-inlretro-dumper-programmer-case-v2
- RetroRGB.com :: Cartridge Cleaning Methods: https://www.retrorgb.com/cleangames.html

<br/><br/>
## Donations:
I went back and forth on this but decided to make a voluntary donation page with [Buy Me A Coffee](https://buymeacoffee.com/cosmickatamari) for these reasons:
- Small donations add up and make it easier to keep projects maintained. 
- It’s a simple way for people who find the project useful to say “thank you."
- It encourages more experiments, side projects, and feature ideas. Also for other projects.
- But remember, it's totally optional ... the code is still there whether anyone donates or not.

<br/><br/>
## Disclaimer:
- This project is not affiliated with the original author (Infinite NES Lives) or any commercial entity.
- The software and modifications are intended solely for personal backup, preservation, and research purposes.
- Use responsibly and ensure that you own any cartridges you dump; the repository does not provide copyrighted ROMs.
- **No warranty is provided; use at your own risk.**
