-- main script that runs application logic and flow

-- =====================================================
-- USER NOTES
-- =====================================================
-- 1- set 'curcart' to point to desired mapper script (around line 60 currently)
-- 2- set 'cart_console' to the currently inserted cartridge (around line 80 currently)
-- 	this will control flow of the script later on which is the 
-- 	location of what you'll need to modify in the next step.
-- 3- call curcart.process function to actually run something:
-- 	NES for example, this is done around line 270ish currently..
-- 	Here are a few NES NROM examples:
--
--	--NROM test & dump to dump.bin file
--	curcart.process( true, true, false, false, false, "ignore/dump.bin", nil, nil)
--
--	--NROM test, erase, & flash flash.bin file
--	curcart.process( true, false, true, true, false, nil, "ignore/flash.bin", nil)
--
--	--NROM test, dump (to dump.bin), then erase.  Next flash flash.bin, lastly dump again to verify.bin
--	curcart.process( true, true, true, true, true, "ignore/dump.bin", "ignore/flash.bin, "ignore/verify.bin)
--
--	Here is the nrom.process function definition:
--	local function process( test, read, erase, program, verify, dumpfile, flashfile, verifyfile)
--	arg 1 - test: this will run some tests on the cart to help determine things like mirroring & flash type
--	arg 2 - read: this will dump the rom memories on the cartridge to 'dumpfile', (done before subequent steps)
--	*The remaining args are only for flash boards purchased from our site:
--	arg 3 - erase: this will erase flash roms on the cartridge
--	arg 4 - program: this will write 'flashfile' to the cartridge
--	arg 5 - verify: this will dump the memories to 'verifyfile', just like read could/did, but done last.
--	arg 6,7,8 files: The relative path of where the files can be found/created from steps above.
--			 You don't have to set unused file names to nil, that was just done for the examples.
--
-- =====================================================


-- initial function called from C main
function main ()


	print("\n")

	local dict = require "scripts.app.dict"
	local cart = require "scripts.app.cart"
	local nes = require "scripts.app.nes"
	local snes = require "scripts.app.snes"
	local dump = require "scripts.app.dump"
	local erase = require "scripts.app.erase"
	local flash = require "scripts.app.flash"
	local swim = require "scripts.app.swim"
	local jtag = require "scripts.app.jtag"
	local ciccom = require "scripts.app.ciccom"
	local fwupdate = require "scripts.app.fwupdate"
	local files = require "scripts.app.files"


-- =====================================================
-- USERS: set curcart to point to the mapper script you would like to use here.
--	The -- comments out a line, so you can add/remove the -- to select/deselect mapper scripts
-- =====================================================
	--cart/mapper specific scripts
	
	--NES mappers
	--local curcart = require "scripts.nes.nrom"
	--local curcart = require "scripts.nes.mmc1"
	--local curcart = require "scripts.nes.unrom"
	--local curcart = require "scripts.nes.cnrom"
	--local curcart = require "scripts.nes.mmc3"
	--local curcart = require "scripts.nes.mmc2"
	--local curcart = require "scripts.nes.mmc4"
	--local curcart = require "scripts.nes.mm2"
	--local curcart = require "scripts.nes.mapper30"	--old version supported by v2.1
	--local curcart = require "scripts.nes.mapper30v2"	--has things required by v2.3.1
	--local curcart = require "scripts.nes.bnrom"
	--local curcart = require "scripts.nes.cdream"
	--local curcart = require "scripts.nes.cninja"
	--local curcart = require "scripts.nes.action53"
	--local curcart = require "scripts.nes.action53_tsop"
	--local curcart = require "scripts.nes.easyNSF"
	--local curcart = require "scripts.nes.fme7"
	--local curcart = require "scripts.nes.dualport"
	
	--SNES boards
	--local curcart = require "scripts.snes.v3"
	--local curcart = require "scripts.snes.lorom_5volt"  --catskull design
	--local curcart = require "scripts.snes.v2proto"
	local curcart = require "scripts.snes.v2proto_hirom"  
	
	-- MAIN GAMEBOY/GAMEBOY COLOR boards 
	-- (SUPER MARIO BROS DELUXE WORKS WITH MBCL on kb=8 * 128)
	-- (POKEMON AND MARIO TENNIS WORKS WITH MBCL on kb=16 * 128)
	--local curcart = require "scripts.gb.romonly"
	--local curcart = require "scripts.gb.mbc1" --WORKING SCRIPT--
	
	--GBA 
	--local curcart = require "scripts.gba.basic"
	
	--SEGA GENESIS / MASTER SYSTEM 
	--local curcart = require "scripts.sega.genesis_v1"
	
	--N64 
	--local curcart = require "scripts.n64.basic"
	
-- =====================================================
-- USERS: set cart_console to the  to point to the mapper script you would like to use here.
-- =====================================================
	--local cart_console = "NES" 	--includes Famicom
	local cart_console = "SNES"
	--local cart_console = "SEGA"
	--local cart_console = "N64"
	--local cart_console = "DMG"	--includes Gameboy/Gameboy Color
	--local cart_console = "GBA"
	--local cart_console = "SMS"

-- =====================================================
-- USERS: Change process options to define interactions with cartridge.
--
-- Note: RAM is not present in all carts, related settings 
-- will be ignored by mappers that don't support RAM.
-- =====================================================
	local process_opts = {
		test = false,
		read = true,
		erase = false,
		program = false,
		verify = false,
		dumpram = true,
		writeram = false,
		dump_filename = "ignore/dump.bin",
		flash_filename = "ignore/flash.bin",
		verify_filename = "ignore/verifyout.bin",
		dumpram_filename = "ignore/ramdump.bin",
		writeram_filename = "",
	}
-- =====================================================
-- USERS: Change console options to define interactions with cartridge.
-- These options can vary from cartridge to cartridge depending on specific hardware it contains.
-- =====================================================
	local console_opts = {
		mirror = nil, -- Only used by latest INL discrete flash boards, set to "H" or "V" to change board mirroring
		prg_rom_size_kb = 256 * 128,	-- Size of NES PRG-ROM in KByte
		chr_rom_size_kb = 8,			-- Size of NES CHR-ROM in KByte
		wram_size_kb = 0,				-- Size of NES PRG-RAM/WRAM in KByte
-- =====================================================
-- USERS: Change the Multiplier Below to change the file size of the rom.
-- =====================================================
	-- GBA/N64/SEGA ROM SPECIFIED -- [Sega 32x carts have not been tested]
	-- 8 * 128 for GB/GBC ( Used Mainly for most GAMEBOY/GAMEBOY COLOR GAMES )
	-- 16 * 128 for GB/GBC/SEGA 16 ( For Some GAMEBOY/GAMEBOY COLOR GAMES )
	-- 64 * 128 for GBA ( Used Mainly) [ Pokemon Roms do not work] (Do not use for N64)
	-- 128 * 128 fo GBA (Used when basic2 script is active)
	-- 128 * 128 for N64 (Used promanantly)
	-- 256 * 128 for GBA ( Used Mainly for GBA Video )
		
		--rom_size_kbyte = 8 * 128,		-- Size of ROM in kilobytes, used for GB/GBC consoles.
		--rom_size_kbyte = 16 * 128, 		-- Size of ROM in kilobytes, used for SEGA 16bit (Genesis/MasterSystem) consoles.		
		--rom_size_kbyte = 32 * 128,		-- Size of ROM in kilobytes, used for SEGA 16bit consoles.
		--rom_size_kbyte = 64 * 128,		-- Size of ROM in kilobytes, used for GBA console.
		--rom_size_kbyte = 128 * 128, 		-- Size of ROM in kilobytes, used for N64 and GBA consoles.
		--rom_size_kbyte = 256 * 128, 		-- Size of ROM in kilobytes, used for GBA (GBA Video) console.		
		
		-- If more convienient, specifying size in megabits is also supported.
		-- rom_size_kbyte = 8, 			-- Size of ROM in megabits, used for non-NES consoles.
	}


	--Firmware update testing

	--active development path (based on makefile in use)
	--fwupdate.update_firmware("../firmware/build_stm/inlretro_stm.bin", nil, true ) --Know what I'm doing? force the update
	--fwupdate.update_firmware("../firmware/build_stm/inlretro_stm.bin", 0x6DC, false) --INL6 skip ram pointer
	--fwupdate.update_firmware("../firmware/build_stm/inlretro_stm.bin", 0x6E8, false) --INL_NES skip ram pointer
	
	--released INL6 path (big square boards)
	--fwupdate.update_firmware("../firmware/build_stm6/inlretro_stm_AV00.bin")
	--fwupdate.update_firmware("../firmware/build_stm6/inlretro_stm_AV01.bin", 0x6DC, false) --INL6 skip ram pointer
	--fwupdate.update_firmware("../firmware/build_stm6/inlretro_stm.bin",      0x6DC, false) --nightly build
	
	--released INL_N path (smaller NESmaker boards)
	--fwupdate.update_firmware("../firmware/build_stmn/inlretro_stm_AV00.bin")
	--fwupdate.update_firmware("../firmware/build_stmn/inlretro_stm_AV01.bin", 0x6E8, false) --INL_NES skip ram pointer
	--fwupdate.update_firmware("../firmware/build_stmn/inlretro_stm.bin",      0x6E8, false) --nightly build
		


--DETECT WHICH CART IS INSERTED, 
--or take user input for manual override 
--VERIFY BASIC CART FUNCTIONALITY
--DON'T PUT THE CART IN ANY WEIRD STATE LIKE SWIM ACTIVATION OR ANYTHING
--	IF SOMETHING LIKE THIS IS DONE, IT MUST BE UNDONE PRIOR TO MOVING ON

--PROCESS USER ARGS ON WHAT IS TO BE DONE WITH CART

	local force_cart = true

	if (force_cart or cart.detect_console(true)) then
		if cart_console == "NES" or cart_console == "Famicom" then
			dict.io("IO_RESET")	
			dict.io("NES_INIT")	
			

			--determined all that could about mapper board
			--set rom types and sizes
			--perform desired operation
			--CART and programmer should be in a RESET condition upon calling the specific script
			
			-- Perform requested operations with provided options.
			curcart.process(process_opts, console_opts)
			

			--always end with and gpio reset incase the script didn't
			dict.io("IO_RESET")	

		elseif cart_console == "SNES" then

			--new SNES code 
			
			--SNES
			-- Only v2proto_hirom currently works with process_opts/console_opts.
			curcart.process(process_opts, console_opts)

			--always end with and gpio reset incase the script didn't
			dict.io("IO_RESET")	

		elseif cart_console == "SEGA" then

			curcart.process(process_opts, console_opts)

			--always end with and gpio reset incase the script didn't
			dict.io("IO_RESET")	

		elseif cart_console == "N64" then

			curcart.process(process_opts, console_opts)
			--always end with and gpio reset incase the script didn't
			dict.io("IO_RESET")	

		elseif cart_console == "DMG" then

			print("testing gameboy")

			dict.io("IO_RESET")	

			curcart.process(process_opts, console_opts)
			--[[	--TEST GB power
				dict.io("GB_POWER_3V")
				print("GBP high 3v GBA")
				jtag.sleep(1)
				dict.io("GB_POWER_5V")
				print("GBP low 5v GB")
				jtag.sleep(1)
				dict.io("GB_POWER_3V")
				print("GBP high 3v GBA")
				jtag.sleep(1)
				dict.io("GB_POWER_5V")
				print("GBP low 5v GB")
				jtag.sleep(1)
				print("GBP reset (pullup) = 3v")
				--]]
			
			--always end with and gpio reset incase the script didn't
			dict.io("IO_RESET")	

		elseif cart_console == "GBA" then

			curcart.process(process_opts, console_opts)

			--always end with and gpio reset incase the script didn't
			dict.io("IO_RESET")	

		elseif cart_console == "SMS" then

			curcart.process(process_opts, console_opts)
			--always end with and gpio reset incase the script didn't
			dict.io("IO_RESET")	
		end

	end


end


main ()

