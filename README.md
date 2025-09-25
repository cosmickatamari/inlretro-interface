# inlretro-interface

Command Line Interface (CLI) for INLretro Dumper-Programmer
https://www.infiniteneslives.com/inlretro.php

Written Using:

* Windows 11 24H2
* PowerShell 7.5.3
* INL Retro firmware 2.3.x

---

As of 9/15/2025, Nintendo Entertainment System section is configured and going through testing.

Project Checklist:
- [x] Nintendo Entertainment System
75 Completed, 1 Failure as of 9/25/2025 (99% Success)

- [ ] Famicom

- [ ] Super Nintendo Entertainment System

- [ ] Super Famicom

- [ ] Nintendo 64

- [ ] Sega Genesis / Mega Drive

- [ ] Gameboy

- [ ] Gameboy Advance

---

The LUA files in this repository have been updated and **are not the original files** included in INL-retro-progdump github repository last commited April 2019 from https://gitlab.com/InfiniteNesLives/INL-retro-progdump.

* The PowerShell file (ps1) needs to be located in the **.\host** directory.
* The file inlretro.lua needs to be located in the **.\host\scripts** directory.
* The file v2proto_hirom.lua needs to be located in the **.\host\scripts\snes** directory.

inlretro.lua edited by Timothy Pritchett -- https://gitlab.com/InfiniteNesLives/INL-retro-progdump/issues/10

v2proto_hirom.lua edited by Zack Carey -- https://gitlab.com/InfiniteNesLives/INL-retro-progdump/issues/18

---

The file will create the needed ignore, games and SRAM folders.
Validation is set to make sure null cartridge names aren't passed (files with spaces are allowed).
The SRAM (save file) can also be dumped, if chosen.
