
-- create the module's table
local cart = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local snes = require "scripts.app.snes"

-- file constants

-- global variables so other modules can use them
cart_console = nil

-- local functions
local function detect_console( debug )

	print("attempting to detect cartridge...");
--	//always start with resetting i/o
	dict.io("IO_RESET")	

--	//TODO check if can detect a cart inserted backwards before continuing

--	//check if NES/Famicom cart 
	dict.io("NES_INIT")	

--	//if PPU /A13 is tied to CIRAM /CE we know it's NES/Famicom
	if nes.jumper_ciramce_ppuA13n(debug) then
--		//NES with 2 screen mirroring
		if debug then print("CIRAM /CE is jumpered to PPU /A13") end
		cart_console = "NES"
	elseif nes.ciramce_inv_ppuA13(debug) then
--		//some boards including INLXO-ROM boards drive CIRAM /CE with inverse of PPU A13
		if debug then print("CIRAM /CE is inverse of PPU A13") end
		cart_console = "NES"
	end
--	TODO check if CIRAM on cartridge or NT CHR-ROM
--
--	if NES/FC determine which if possible
--	also possible that this could catch failed detections above which is current case with VRC6
--	Famicom has audio in and audio out pins connected to each other
--	For this to pass with a NES cart EXP6 would have to be jumpered to EXP0 for some strange reason
--	might fail if expansion audio mixing circuitry foils the check above
--	but worst case we detected NES when famicom which isn't big deal..
	if nes.jumper_famicom_sound(debug) then
		if debug then print("Famicom audio jumper found") end
		cart_console = "Famicom"
	end

--	//if couldn't detect NES/FC check for SNES cartridge
--	//want to keep from outputting on EXP bus if NES cart was found
	if cart_console == nil then

		--currently detect SNES cartridge by reading reset vector
		--ensuring it's valid by range and differing between banks
		dict.io("SNES_INIT")	

		local bank0vect = snes.read_reset_vector( 0, debug ) --actual reset vector
		local bank1vect = snes.read_reset_vector( 1, debug )
		--bank 0 and bank 1 would have same reset vector on a NES cart
		--these probably differ on a SNES if there's more than 32/64KB of ROM.

		--fake cart detection of erased board for now
		cart_console = "SNES"

		if bank0vect ~= bank1vect then
			if (bank0vect >= 0x8000) and (bank0vect < 0xFFFA) then
				if debug then print("valid SNES reset vector found that differs between bank0 & bank1") end
				cart_console = "SNES"
			end
		else
			if debug then print("invalid SNES reset vector or same vector found on bank0 & bank1") end
		end

--		//now it's possible that rom is there, but data is 0xFF so above test would fail
--		//one option would be to drive bus low for short period and see if bus can be
--		//driven low.  This could damage pin drivers though, best to create command in 
--		//firmware to perform this to limit to one CPU cycle instead of USB xfr times
--
--		//Prob best to check if able to read flash ID's if reset vector data is 0xFF
--		//Since reset vector being 0xFF prob means it's blank flash cart..
--
--		//playable SNES carts should have data somewhere in reset vector...
--	}
	end
--
--	//always end with resetting i/o
	dict.io("IO_RESET")	

	if cart_console then
		print(cart_console, "cartridge detected!")
		return true
	else
		print("unable to detect cartridge type")
		return false
	end
--	switch (cart->console) {
--		case NES_CART: printf("NES cartridge detected!\n");	
--			break;
--		case FC_CART: printf("Famicom cartridge detected!\n");	
--			break;
--		case SNES_CART: printf("SNES cartridge detected!\n");	
--			break;
--		case BKWD_CART: log_err("CARTRIDGE INSERTED BACKWARDS!!!\n");	
--			//TODO detection not yet implemented need to look over connector pinouts
--			break;
--		case UNKNOWN: printf("Unable to detect cartridge...\n");
--			//TODO error out properly
--			break;
--		default:
--			sentinel("cartridge console element got set to something unsupported.");
--	}
--}

end



-- call functions desired to run when script is called/imported


-- functions other modules are able to call
cart.detect_console = detect_console

-- return the module's table
return cart
