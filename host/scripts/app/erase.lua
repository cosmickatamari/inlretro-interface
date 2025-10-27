
-- create the module's table
local erase = {}

-- import required modules
local dict = require "scripts.app.dict"
--local swim = require "scripts.app.swim"
local snes = require "scripts.app.snes"

-- file constants

-- local functions
local function erase_nes()

	local rv = nil

	print("erasing_nrom");

	dict.io("IO_RESET")
	dict.io("NES_INIT")
	
	print("erasing PRG-ROM");
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x80)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x10)
	rv = dict.nes("NES_CPU_RD", 0x8000)

	local i = 0

	while ( rv ~= 0xFF ) do
		rv = dict.nes("NES_CPU_RD", 0x8000)
		i = i + 1
	end
	print(i, " done erasing prg.\n");

	print("erasing CHR-ROM");
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
	dict.nes("NES_PPU_WR", 0x1555, 0x80)
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
	dict.nes("NES_PPU_WR", 0x1555, 0x10)
	rv = dict.nes("NES_PPU_RD", 0x0000)

	local i = 0

	while ( rv ~= 0xFF ) do
		rv = dict.nes("NES_PPU_RD", 0x0000)
		i = i + 1
	end
	print(i, " done erasing chr.\n");

end


-- local functions
local function erase_snes(debug)

	local rv = nil

	print("erasing SNES takes about 30sec");

--	dict.io("IO_RESET")
	dict.io("SNES_INIT")
	
	--WR $AAA:AA $555:55 $AAA:AA
	dict.snes("SNES_SET_BANK", 0x00)

	--put cart in program mode
	snes.prgm_mode()

	dict.snes("SNES_ROM_WR", 0x0AAA, 0xAA)
	dict.snes("SNES_ROM_WR", 0x0555, 0x55)
	dict.snes("SNES_ROM_WR", 0x0AAA, 0x80)
	dict.snes("SNES_ROM_WR", 0x0AAA, 0xAA)
	dict.snes("SNES_ROM_WR", 0x0555, 0x55)
	dict.snes("SNES_ROM_WR", 0x0AAA, 0x10)

	--exit program mode
	snes.play_mode()

	rv = dict.snes("SNES_ROM_RD", 0x0000)

	local i = 0

	while ( rv ~= 0xFF ) do
		rv = dict.snes("SNES_ROM_RD", 0x0000)
		i = i + 1
		if debug then print(" ", i,":", string.format("%x",rv)) end
	end
	print(i, " done erasing snes.\n");

	--put cart in program mode
--	swim.start()
	snes.prgm_mode()

	--reset flash
	dict.snes("SNES_ROM_WR", 0x0000, 0xF0)

	--return to PLAY mode
	print("erase play")
	snes.play_mode()
	print("erase play")

end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
erase.erase_nes = erase_nes
erase.erase_snes = erase_snes

-- return the module's table
return erase
