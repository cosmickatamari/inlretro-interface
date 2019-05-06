# inlretro-interface

Command Line Interface (CLI) for INLretro Dumper-Programmer
https://www.infiniteneslives.com/inlretro.php

---
---

Written Using:

* Windows 10 (build 1803)
* INL Retro firmware 2.3.x

---

The LUA files in this repository have been updated and **are not the original files** included in INL-retro-progdump github repository last commited April 2019 from https://gitlab.com/InfiniteNesLives/INL-retro-progdump.

* The CMD file needs to be located in the **.\host** directory.
* The file inlretro.lua needs to be located in the **.\host\scripts** directory.
* The file v2proto_hirom.lua needs to be located in the **.\host\scripts\snes** directory.

inlretro.lua edited by Timothy Pritchett -- https://gitlab.com/InfiniteNesLives/INL-retro-progdump/issues/10
v2proto_hirom.lua edited by Zack Carey -- https://gitlab.com/InfiniteNesLives/INL-retro-progdump/issues/18

---

The file will create the needed ignore and games folders.
Validation is set to make sure null cartridge names aren't passed (files with spaces are allowed).
The SRAM (save file) is also automatically dumped.

---

At this time, 05/05/2019, only SNES is built out and in testing, even though menus for the other systems appear.

- [ ] Nintendo

- [ ] Famicom

- [x] Super Nintendo

- [x] Super Famicom

- [ ] Nintendo 64

- [ ] Super Famicom

- [ ] Sega Genesis / Mega Drive

- [ ] Gameboy

- [ ] Gameboy Advance

---

Any issues, please let me know with screenshots. While this is simply a frontend, it's purpose is to make sure correct dumping of cartridges occurs.
