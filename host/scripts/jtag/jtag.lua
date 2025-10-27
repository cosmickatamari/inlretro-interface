
-- create the module's table
local jtag = {}

-- import required modules
local dict = require "scripts.app.dict"
local files = require "scripts.app.files"
local time = require "scripts.app.time"

local pbje = require "scripts.jtag.pbje"

--set cpld to which ever device is being used
--local cpld = require "scripts.jtag.lc4000v"
local cpld = require "scripts.jtag.machXO256"


local function check_IDCODE(debug)

	local idcode_len = 32 --hex digits

	--first put/verify jtag statemachine is in RESET
	pbje.goto_state("RESET")

	--by default jtag should be in IDCODE or BYPASS if IDCODE not present
	--The TDI pin doesn't even have to be working to scan out IDCODE by this means
	
	--let's just put in IDCODE mode
	---[[
	--Mach XO verify ID code
--	! Check the IDCODE
--
--	! Shift in IDCODE(0x16) instruction
--	SIR     8       TDI  (16);
	pbje.goto_state("SHIFT_IR") pbje.scan( 8, 0x16)

	--return to default state after SIR
	--doesn't appear to actually be needed
--	pbje.goto_state("PAUSE_IR")

--	SDR     32      TDI  (FFFFFFFF)
--	                TDO  (01281043)
--	                MASK (FFFFFFFF);
	--pbje.goto_state("SHIFT_DR")
	--rv = pbje.scan( 32, "HIGH", true)
	--print("return data:", string.format(" %X, ",rv))
	--]]



	--change to SCAN-DR state
	pbje.goto_state("SHIFT_DR")

	--scan out 32bit IDCODE while scanning in 1's to TDI
	rv = pbje.scan( 32, "HIGH", true )
	if debug then print("return data:", string.format("%X",rv)) end
	rv =                  string.format("%16.16X",rv)
	if debug then print(rv) end
	rv = string.sub(rv, ((64-idcode_len)/4)+1, 64/4)

	--print("return data:", string.format(" %X, ",rv))
	print("read idcode:", rv)

	--if( rv == 0x1281043 ) then
	if( rv == "01281043" ) then
	-- Mach XO 256   01281043
	-- 4032v	(01805043)
	-- 4064v	(01809043)
	--
	-- 9536xl
	-- //Loading device with 'idcode' instruction.
	-- SIR 8 TDI (fe) SMASK (ff) ;
	-- SDR 32 TDI (00000000) SMASK (ffffffff) TDO (f9602093) MASK (0fffffff) ;
	--
	-- 9572xl
	-- //Loading device with 'idcode' instruction.
	-- SIR 8 TDI (fe) SMASK (ff) ;
	-- SDR 32 TDI (00000000) SMASK (ffffffff) TDO (f9604093) MASK (0fffffff) ;
	-- test read gives 59604093
		print("IDCODE matches MACHXO-256")
	--elseif ( rv==0x01805043 ) then
	elseif ( rv=="01805043" ) then
		print("IDCODE matches LC4032V")
	--elseif ( rv==0x01809043 ) then
	elseif ( rv=="01809043" ) then
		print("IDCODE matches LC4064V")
	else
		print("no match for IDCODE")
	end
	
	--xilinx IDCODE command is different
	--//Loading device with 'idcode' instruction.
	--SIR 8 TDI (fe) SMASK (ff) ;
	--SDR 32 TDI (00000000) SMASK (ffffffff) TDO (f9602093) MASK (0fffffff) ;
--	pbje.goto_state("SHIFT_IR")
--	pbje.scan( 8, 0xfe)
--	pbje.goto_state("SHIFT_DR")
--	rv = pbje.scan( 32, "HIGH", true)
--	print("return data:", string.format(" %X, ",rv))

end



local function run_jtag( debug )

	local rv

	--setup lua portion of jtag engine
	pbje.init("INLRETRO")

	--initialize JTAG port on USB device
	dict.io("JTAG_INIT", "JTAG_ON_EXP0_3") --NES
	--dict.io("JTAG_INIT", "JTAG_ON_SNES_CTL") --SNES
	
	--open jedec file
	local filename = "ignore/TKROM_prod_p512_w8_crom256_v4_0_0_currelease.jed"
	--local filename = "ignore/8mb_v2_0p.jed"

	--first put/verify jtag statemachine is in RESET
	pbje.goto_state("RESET")

	check_IDCODE()


	--cpld.erase()
	---[[


	--program CPLD
	local jed_file = assert(io.open(filename, "rb"))


	--find and consume the "L00000" start of usemap token in jedec file
	files.readtill_line(jed_file, "L00000", false)
	check_IDCODE()
	cpld.program(jed_file, false)

	--close jedec file
	assert(jed_file:close())
	--]]

	
	--verify programming
	--open jedec file
	--local jed_file = assert(io.open("ignore/8mb_v2_0p.jed", "rb"))
	--local jed_file = assert(io.open("ignore/TKROM_prod_p512_w8_crom256_v4_0_0_currelease.jed", "rb"))
	local jed_file = assert(io.open(filename, "rb"))

	--check_IDCODE()
	--find and consume the "L00000" start of usemap token in jedec file
	files.readtill_line(jed_file, "L00000")
	--jed file needs to be read up to and consumed the L00000 command line so only the bit stream follows
	cpld.verify(jed_file, false)

	--close jedec file
	assert(jed_file:close())

	--[[

	--secure CPLD
	cpld.secure()

	--can usercode be verified when secured..? NOPE!
	--verify programming
	--open jedec file
	local jed_file = assert(io.open("ignore/8mb_v2_0p.jed", "rb"))

	check_IDCODE()
	--find and consume the "L00000" start of usemap token in jedec file
	files.readtill_line(jed_file, "L00000")
	--jed file needs to be read up to and consumed the L00000 command line so only the bit stream follows
	cpld.verify(jed_file, false)

	--close jedec file
	assert(jed_file:close())
	
	--]]

end

-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
jtag.wait_pbje_done = wait_pbje_done
jtag.run_jtag = run_jtag
--jtag.sleep = sleep

-- return the module's table
return jtag
