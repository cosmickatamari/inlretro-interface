-- Main script that runs application logic and flow

-- =====================================================
-- USER NOTES
-- =====================================================
-- 1. Set 'curcart' to point to desired mapper script (around line 60)
-- 2. Set 'cart_console' to the currently inserted cartridge (around line 80)
--    This will control flow of the script later on
-- 3. Call curcart.process function to actually run something
--
-- NES NROM examples:
--   -- NROM test & dump to dump.bin file
--   curcart.process(true, true, false, false, false, "ignore/dump.bin", nil, nil)
--
--   -- NROM test, erase, & flash flash.bin file
--   curcart.process(true, false, true, true, false, nil, "ignore/flash.bin", nil)
--
--   -- NROM test, dump (to dump.bin), then erase. Next flash flash.bin, lastly dump again to verify.bin
--   curcart.process(true, true, true, true, true, "ignore/dump.bin", "ignore/flash.bin", "ignore/verify.bin)
--
-- nrom.process function definition:
--   local function process(test, read, erase, program, verify, dumpfile, flashfile, verifyfile)
--   arg 1 - test: run tests on cart to determine mirroring & flash type
--   arg 2 - read: dump ROM memories to 'dumpfile' (done before subsequent steps)
--   *The remaining args are only for flash boards purchased from our site:
--   arg 3 - erase: erase flash ROMs on the cartridge
--   arg 4 - program: write 'flashfile' to the cartridge
--   arg 5 - verify: dump memories to 'verifyfile', just like read could/did, but done last
--   arg 6,7,8 files: Relative path of where files can be found/created from steps above
--                    You don't have to set unused file names to nil, that was just done for examples
-- =====================================================

-- Initial function called from C main
function main()
	print("\n")

	-- Core required modules
	local dict = require "scripts.app.dict"
	local cart = require "scripts.app.cart"
	local nes = require "scripts.app.nes"
	local snes = require "scripts.app.snes"
	
	-- Optional modules (for firmware updates - currently commented out)
	local fwupdate = require "scripts.app.fwupdate"


	-- =====================================================
	-- USERS: Set curcart to point to the mapper script you would like to use here.
	-- The -- comments out a line, so you can add/remove the -- to select/deselect mapper scripts
	-- =====================================================
	-- Cart/mapper specific scripts
	
	-- NES mappers
	--local curcart = require "scripts.nes.nrom"
	--local curcart = require "scripts.nes.mmc1"
	--local curcart = require "scripts.nes.unrom"
	--local curcart = require "scripts.nes.cnrom"
	--local curcart = require "scripts.nes.mmc3"
	--local curcart = require "scripts.nes.mmc2"
	--local curcart = require "scripts.nes.mmc4"
	--local curcart = require "scripts.nes.mm2"
	--local curcart = require "scripts.nes.mapper30"      -- Old version supported by v2.1
	--local curcart = require "scripts.nes.mapper30v2"  -- Has things required by v2.3.1
	--local curcart = require "scripts.nes.bnrom"
	--local curcart = require "scripts.nes.cdream"
	--local curcart = require "scripts.nes.cninja"
	--local curcart = require "scripts.nes.action53"
	--local curcart = require "scripts.nes.action53_tsop"
	--local curcart = require "scripts.nes.easyNSF"
	--local curcart = require "scripts.nes.fme7"
	--local curcart = require "scripts.nes.dualport"
	
	-- SNES boards
	--local curcart = require "scripts.snes.v3"
	--local curcart = require "scripts.snes.lorom_5volt"  -- Catskull design
	--local curcart = require "scripts.snes.v2proto"
	local curcart = require "scripts.snes.v2proto_hirom"  -- Becoming the master SNES script
	
	-- Game Boy boards
	--local curcart = require "scripts.gb.romonly"
	--local curcart = require "scripts.gb.mbc1"
	
	-- GBA
	--local curcart = require "scripts.gba.basic"
	
	-- Sega Genesis
	--local curcart = require "scripts.sega.genesis_v1"
	
	-- N64
	--local curcart = require "scripts.n64.basic"
	
	-- =====================================================
	-- USERS: Set cart_console to the currently inserted cartridge type
	-- =====================================================
	--local cart_console = "NES"      -- Includes Famicom
	local cart_console = "SNES"
	--local cart_console = "SEGA"
	--local cart_console = "N64"
	--local cart_console = "DMG"
	--local cart_console = "GBA"
	--local cart_console = "SMS"

	-- =====================================================
	-- USERS: Change process options to define interactions with cartridge
	-- Note: RAM is not present in all carts, related settings will be ignored by mappers that don't support RAM
	-- =====================================================
	local process_opts = {
		test = false,
		read = false,
		erase = false,
		program = false,
		verify = true,
		dumpram = false,
		writeram = true,
		dump_filename = "",
		flash_filename = "",
		verify_filename = "",
		dumpram_filename = "",
		writeram_filename = "games/Earthbound.srm",
	}
	
	-- =====================================================
	-- USERS: Change console options to define interactions with cartridge
	-- These options can vary from cartridge to cartridge depending on specific hardware it contains
	-- =====================================================
	local console_opts = {
		mirror = nil,              -- Only used by latest INL discrete flash boards, set to "H" or "V" to change board mirroring
		prg_rom_size_kb = 256 * 128,  -- Size of NES PRG-ROM in KB
		chr_rom_size_kb = 8,          -- Size of NES CHR-ROM in KB
		wram_size_kb = 0,              -- Size of NES PRG-RAM/WRAM in KB
		rom_size_kbyte = 8 * 128,     -- Size of ROM in kilobytes, used for non-NES consoles
	}
	
	-- Firmware update testing (commented out - uncomment to use)
	-- Active development path (based on makefile in use)
	--fwupdate.update_firmware("../firmware/build_stm/inlretro_stm.bin", nil, true)  -- Know what I'm doing? Force the update
	--fwupdate.update_firmware("../firmware/build_stm/inlretro_stm.bin", 0x6DC, false) -- INL6 skip ram pointer
	--fwupdate.update_firmware("../firmware/build_stm/inlretro_stm.bin", 0x6E8, false) -- INL_NES skip ram pointer
	
	-- Released INL6 path (big square boards)
	--fwupdate.update_firmware("../firmware/build_stm6/inlretro_stm_AV00.bin")
	--fwupdate.update_firmware("../firmware/build_stm6/inlretro_stm_AV01.bin", 0x6DC, false) -- INL6 skip ram pointer
	--fwupdate.update_firmware("../firmware/build_stm6/inlretro_stm.bin", 0x6DC, false)        -- Nightly build
	
	-- Released INL_N path (smaller NESmaker boards)
	--fwupdate.update_firmware("../firmware/build_stmn/inlretro_stm_AV00.bin")
	--fwupdate.update_firmware("../firmware/build_stmn/inlretro_stm_AV01.bin", 0x6E8, false) -- INL_NES skip ram pointer
	--fwupdate.update_firmware("../firmware/build_stmn/inlretro_stm.bin", 0x6E8, false)       -- Nightly build
	
	-- Detect which cart is inserted, or take user input for manual override
	-- Verify basic cart functionality
	-- Don't put the cart in any weird state like SWIM activation or anything
	-- If something like this is done, it must be undone prior to moving on
	-- Process user args on what is to be done with cart
	
	local force_cart = true

	if (force_cart or cart.detect_console(true)) then
		if cart_console == "NES" or cart_console == "Famicom" then
			dict.io("IO_RESET")
			dict.io("NES_INIT")
			
			-- Determined all that could about mapper board
			-- Set ROM types and sizes
			-- Perform desired operation
			-- CART and programmer should be in a RESET condition upon calling the specific script
			curcart.process(process_opts, console_opts)
			
			-- Always end with GPIO reset in case the script didn't
			dict.io("IO_RESET")
			
		elseif cart_console == "SNES" then
			-- Only v2proto_hirom currently works with process_opts/console_opts
			curcart.process(process_opts, console_opts)
			
			-- Always end with GPIO reset in case the script didn't
			dict.io("IO_RESET")
			
		elseif cart_console == "SEGA" then
			curcart.process(process_opts, console_opts)
			
			-- Always end with GPIO reset in case the script didn't
			dict.io("IO_RESET")
			
		elseif cart_console == "N64" then
			curcart.process(process_opts, console_opts)
			
			-- Always end with GPIO reset in case the script didn't
			dict.io("IO_RESET")
			
		elseif cart_console == "DMG" then
			print("Testing Game Boy")
			dict.io("IO_RESET")
			
			curcart.process(process_opts, console_opts)
			--[[
			-- TEST GB power
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
			
			-- Always end with GPIO reset in case the script didn't
			dict.io("IO_RESET")
			
		elseif cart_console == "GBA" then
			curcart.process(process_opts, console_opts)
			
			-- Always end with GPIO reset in case the script didn't
			dict.io("IO_RESET")
			
		elseif cart_console == "SMS" then
			curcart.process(process_opts, console_opts)
			
			-- Always end with GPIO reset in case the script didn't
			dict.io("IO_RESET")
		end
	end
end

main()

