-- PAUL'S BASIC JTAG ENGINE
-- this module keeps track of JTAG statemachine current state
-- so it can then know how to get to a different state
-- This module is responsible for generating the TMS, TCK, TDI, TDO 
-- pin toggling sequences necessary and send basic commands over
-- to the PBJE running on the INLretro, or the cartridge mcu
-- The actual engine running on the INLretro/cartridge is pretty dumb
-- but has the hardware/physical interface, and the 'intelligence' resides here.

-- create the module's table
local pbje = {}

-- import required modules
local dict = require "scripts.app.dict"
local files = require "scripts.app.files"
local time = require "scripts.app.time"

-- file constants
local pbje_loc	--physical location of PBJE engine so this script known how to set engine registers
local cur_jtag_state

local clock = os.clock
local function sleep(n)  -- seconds
	local t0 = clock()
	while clock() - t0 <= n do end
end
-- warning: clock can eventually wrap around for sufficiently large n
-- (whose value is platform dependent).  Even for n == 1, clock() - t0
-- might become negative on the second that clock wraps.
    
-- local functions

-- initialize lua portions of JTAG
-- JTAG hardware port may be virtuatlized by placing PBJE "Paul's Basic JTAG Engine" 
-- inside the board itself (ie CIC mcu) instead of on the inlretro programmer
-- in these types of cases, want the jtag high level functions to be independent of
-- where the PBJE engine is located physically.
local function init( location )

	pbje_loc = location

end

local function wait_pbje_done( num_polls, debug )

	local status

	while( num_polls > 0 ) do

		status = dict.jtag("GET_STATUS") 
		if( status == op_jtag["PBJE_DONE"]) then
			if( debug) then print("PBJE done num polls left:", num_polls) end
			return true
		else
			if( debug) then print("PBJE wasn't done, status:", status) end
		end
		num_polls = num_polls - 1
	end

	print("JTAG timed out while waiting for PBJE_DONE")
	return false

end

local function set_data_2B( data )

	--check args
	if( data > 0xFFFF  )then
		print("ERROR data:", data, "too large for set_data_2B")
		return false
	end

	--set data based on pjbe location
	if( pbje_loc == nil ) then
		print("ERROR, pbje location must be initialized prior to setting registers")

	elseif( pbje_loc == "INLRETRO" ) then
		dict.jtag("SET_2B_DATA", data)
		return true

	else 
		print("ERROR, pbje location:", pbje_loc, "not recognized by set_data_2B function.")
	end

	--failed if got to this point without returning
	return false

end

local function set_clk( num_clks )

	--check args
	if( num_clks == 256 ) then
		num_clks = 0
	elseif( num_clks > 255 or num_clks < 0  )then
		print("ERROR num clks:", num_clks, "exceeds range of 1-256")
		return false
	end

	--set num_clks based on pjbe location
	if( pbje_loc == nil ) then
		print("ERROR, pbje location must be initialized prior to setting registers")

	elseif( pbje_loc == "INLRETRO" ) then
		dict.jtag("SET_NUMCLK", num_clks)
		return true

	else 
		print("ERROR, pbje location:", pbje_loc, "not recognized by set_clk function.")
	end

	--failed if got to this point without returning
	return false

end

local function set_run_get_cmd( command )

	local rv

	--check args
	if not op_jtag[command] then
		print("ERROR command:", command, "is not defined in shared_dict_jtag.h")
		return false
	end

	--set command based on pjbe location
	if( pbje_loc == nil ) then
		print("ERROR, pbje location must be initialized prior to setting registers")

	elseif( pbje_loc == "INLRETRO" ) then
		--TODO provide flag if don't want to wait on immediate processing (for long data streams)
		rv = dict.jtag("SET_CMD_WAIT", command)
		--verify command was done
		if(rv ~= op_jtag["PBJE_DONE"]) then print("error JTAG not done, status: ", rv) end
		return true

	else 
		print("ERROR, pbje location:", pbje_loc, "not recognized by set_run_get_cmd function.")
	end

	--failed if got to this point without returning
	return false

end

-- clocks JTAG statemachine with TMS set to 1 enough times to guarantee RESET state
-- prereq: JTAG PBJEngine must be initialized
local function reset_statemachine( debug )

	local rv
	--only takes 5 clocks with TMS high to force into RESET from any state
	set_clk(8)
	set_run_get_cmd("PBJE_CLOCK1")	--no data needed for this opcode, forces TMS to 1

	--we know the state machine is in RESET now
	cur_jtag_state = "RESET"
end



-- current and next JTAG state must be stable (RESET, IDLE, PAUSE-DR/IR) or SHIFT-DR/IR
-- only exception is reset will blindly force RESET by clocking with TMS high

-- other gotcha is that the last TDI bit is latched when transitioning out of SHIFT-DR/IR
-- state.  So data scans must go from shift to exit1 to complete.  Therefore it doesn't make
-- sense to enter this function in a SHIFT-DR/IR state, doing so would scan in one bit when
-- exiting SHIFT state


local function goto_state( new_jtag_state )

	local clk, tms 

	--if new state is RESET then, just blindly clock with TMS high
	if( new_jtag_state == "RESET" ) then
		reset_statemachine()
		cur_jtag_state = "RESET"
		return true
	end

	--current state is stored in cur_jtag_state
	if( cur_jtag_state == "RESET" ) then
		if( new_jtag_state == "IDLE" ) then
			clk = 1
			tms = 0	-- IDLE-RESET

		elseif( new_jtag_state == "SHIFT_DR" ) then
			clk = 4
			tms = 0x02 -- SHIFT-CAP-SELDR-IDLE 0010

		elseif( new_jtag_state == "SHIFT_IR" ) then
			clk = 5
			tms = 0x06 -- SHIFT-CAP-SELIR-SELDR-IDLE 00110

		elseif( new_jtag_state == "PAUSE_DR" ) then
			clk = 5
			tms = 0x0a -- PAUSE-EX1-CAP-SELDR-IDLE 01010

		elseif( new_jtag_state == "PAUSE_IR" ) then
			clk = 6
			tms = 0x16 -- PAUSE-EX1-CAP-SELIR-SELDR-IDLE 010110

		else
			print("ERROR!!!  new JTAG state:", new_jtag_state, "isn't stable, nor shift state!!!")
			return nil
		end
			

	elseif( cur_jtag_state == "IDLE" ) then
		if( new_jtag_state == "IDLE" ) then
			clk = 1
			tms = 0	-- IDLE-IDLE

		elseif( new_jtag_state == "SHIFT_DR" ) then
			clk = 3
			tms = 0x01 -- SHIFT-CAP-SELDR 001

		elseif( new_jtag_state == "SHIFT_IR" ) then
			clk = 4
			tms = 0x03 -- SHIFT-CAP-SELIR-SELDR 0011

		elseif( new_jtag_state == "PAUSE_DR" ) then
			clk = 4
			tms = 0x05 -- PAUSE-EX1-CAP-SELDR 0101

		elseif( new_jtag_state == "PAUSE_IR" ) then
			clk = 5
			tms = 0x0b -- PAUSE-EX1-CAP-SELIR-SELDR 01011
		else
			print("ERROR!!!  new JTAG state:", new_jtag_state, "isn't stable, nor shift state!!!")
			return nil
		end

	elseif( cur_jtag_state == "EXIT1_DR" ) then
		if( new_jtag_state == "IDLE" ) then
			clk = 2
			tms = 0x01 -- IDLE-UP 01

		elseif( new_jtag_state == "SHIFT_DR" ) then
			clk = 3
			tms = 0x02 -- SHIFT-EX2-PAUSE 010

		elseif( new_jtag_state == "SHIFT_IR" ) then
			clk = 5
			tms = 0x07 -- SHIFT-CAP-SELIR-SELDR-UP 0_0111

		elseif( new_jtag_state == "PAUSE_DR" ) then
			clk = 1
			tms = 0x00 -- PAUSE 0

		elseif( new_jtag_state == "PAUSE_IR" ) then
			clk = 6
			tms = 0x17 -- PAUSE-EX1-CAP-SELIR-SELDR-UP 01_0111
		else
			print("ERROR!!!  new JTAG state:", new_jtag_state, "isn't stable, nor shift state!!!")
			return nil
		end

	elseif( cur_jtag_state == "EXIT1_IR" ) then
		if( new_jtag_state == "IDLE" ) then
			clk = 2
			tms = 0x01 -- IDLE-UP 01

		elseif( new_jtag_state == "SHIFT_DR" ) then
			clk = 4
			tms = 0x03 -- SHIFT-CAP-SELIR-UP 0011

		elseif( new_jtag_state == "SHIFT_IR" ) then
			clk = 3
			tms = 0x02 -- SHIFT-EX2-PAUSE 010

		elseif( new_jtag_state == "PAUSE_DR" ) then
			clk = 5
			tms = 0x0b -- PAUSE-EX1-CAP-SELIR-UP 0_1011

		elseif( new_jtag_state == "PAUSE_IR" ) then
			clk = 1
			tms = 0x00 -- PAUSE 0
		else
			print("ERROR!!!  new JTAG state:", new_jtag_state, "isn't stable, nor shift state!!!")
			return nil
		end


	elseif( cur_jtag_state == "SHIFT_DR" ) then
--		if( new_jtag_state == "IDLE" ) then
--			clk = 3
--			tms = 0x03 -- IDLE-UP-EX1 011
--
--	--	elseif( new_jtag_state == "SHIFT_DR" ) then
--	--		--nothing to do
--
--		elseif( new_jtag_state == "SHIFT_IR" ) then
--			clk = 6
--			tms = 0x0f -- SHIFT-CAP-SELIR-SELDR-UP-EX1 00_1111
--
--		elseif( new_jtag_state == "PAUSE_DR" ) then
--			clk = 2
--			tms = 0x01 -- PAUSE-EX1 01
--
--		elseif( new_jtag_state == "PAUSE_IR" ) then
--			clk = 7
--			tms = 0x2f -- PAUSE-EX1-CAP-SELIR-SELDR-UP-EX1 010_1111
--		else
--
			print("ERROR!!!  can't change state starting from SHIFT-IR/DR as a bit will be scanned in when exitting")
			return nil
--		end

	elseif( cur_jtag_state == "SHIFT_IR" ) then
--		if( new_jtag_state == "IDLE" ) then
--			clk = 3
--			tms = 0x03 -- IDLE-UP-EX1 011
--
--		elseif( new_jtag_state == "SHIFT_DR" ) then
--			clk = 5
--			tms = 0x07 -- SHIFT-CAP-SELIR-UP-EX1 0_0111
--
--	--	elseif( new_jtag_state == "SHIFT_IR" ) then
--	--		--nothing to do
--
--		elseif( new_jtag_state == "PAUSE_DR" ) then
--			clk = 6
--			tms = 0x17 -- PAUSE-EX1-CAP-SELIR-UP-EX1 01_0111
--
--		elseif( new_jtag_state == "PAUSE_IR" ) then
--			clk = 2
--			tms = 0x01 -- PAUSE-EX1 01
--		else
			print("ERROR!!!  can't change state starting from SHIFT-IR/DR as a bit will be scanned in when exitting")
			return nil
--		end

	elseif( cur_jtag_state == "PAUSE_DR" ) then
		if( new_jtag_state == "IDLE" ) then
			clk = 3
			tms = 0x03 -- IDLE-UP-EX2 011

		elseif( new_jtag_state == "SHIFT_DR" ) then
			clk = 2
			tms = 0x01 -- SHIFT-EX2 01

		elseif( new_jtag_state == "SHIFT_IR" ) then
			clk = 6
			tms = 0x0f -- SHIFT-CAP-SELIR-SELDR-UP-EX2 00_1111

		elseif( new_jtag_state == "PAUSE_DR" ) then
			--nothing to do

		elseif( new_jtag_state == "PAUSE_IR" ) then
			clk = 7
			tms = 0x2f -- PAUSE-EX1-CAP-SELIR-SELDR-UP_EX2 010_1111
		else
			print("ERROR!!!  new JTAG state:", new_jtag_state, "isn't stable, nor pre-shift state!!!")
			return nil
		end

	elseif( cur_jtag_state == "PAUSE_IR" ) then
		if( new_jtag_state == "IDLE" ) then
			clk = 3
			tms = 0x03 -- IDLE-UP-EX2 011

		elseif( new_jtag_state == "SHIFT_DR" ) then
			clk = 5
			tms = 0x07 -- SHIFT-CAP-SELDR-UP-EX2 0_0111

		elseif( new_jtag_state == "SHIFT_IR" ) then
			clk = 2
			tms = 0x01 -- SHIFT-EX2 01

		elseif( new_jtag_state == "PAUSE_DR" ) then
			clk = 6
			tms = 0x17 -- PAUSE-EX1-CAP-SELDR-UP_EX2 01_0111

		elseif( new_jtag_state == "PAUSE_IR" ) then
			--nothing to do
		else
			print("ERROR!!!  new JTAG state:", new_jtag_state, "isn't stable, nor pre-shift state!!!")
			return nil
		end

	else
		print("ERROR!!!  current JTAG state:", cur_jtag_state, "isn't stable, nor shift state!!!")
		return nil
	end

	--set PJBE register values and give state change command
	set_data_2B(tms)
	set_clk(clk)
	set_run_get_cmd("PBJE_STATE_CHG")

	--update jtag state
	cur_jtag_state = new_jtag_state

	return true

end


-- return data scanned out

local function scan( numbits, data_in, data_out, debug )

	--check to ensure current state is SHIFT-IR/DR
	if not( cur_jtag_state == "SHIFT_IR" or cur_jtag_state == "SHIFT_DR") then
		print("ERROR, jtag state must be SHIFT-IR/DR in order to scan data in/out")
		return nil
	end


	--TODO analyze numbits to determine if needs to be split into several shorter scans
	--currently all scans exit at end of shift
	set_clk(numbits)
	
	--scan out with TDI high
	if( data_in == "HIGH" and data_out ) then
		set_run_get_cmd("PBJE_TDO_SCAN1")
		data_out = dict.jtag("GET_8B_DATA")
--		if numbits <= 6*8 then
--			data_out = dict.jtag("GET_8B_DATA")
--		else
--			data_out = dict.jtag("GET_32B_DATA")
--		end

	--scan out with TDI low
	elseif( data_in == "LOW" and data_out ) then
		set_run_get_cmd("PBJE_TDO_SCAN0")
		data_out = dict.jtag("GET_8B_DATA")
--		if numbits <= 6*8 then
--			data_out = dict.jtag("GET_8B_DATA")
--		else
--			data_out = dict.jtag("GET_32B_DATA")
--		end

	--scan in with TDI high
	elseif( data_in == "HIGH" and not data_out ) then
		set_run_get_cmd("PBJE_TDO_SCAN1")

	--scan in with TDI low
	elseif( data_in == "LOW" and not data_out ) then
		set_run_get_cmd("PBJE_TDO_SCAN0")

	--scan in ignoring TDO
	elseif( data_in and not data_out ) then
		--TODO support more than 16/64bits by calling TDI_SCAN_HOLD
		set_data_2B(data_in)
		set_run_get_cmd("PBJE_TDI_SCAN")

	--scan in data and capture scan out
	elseif( data_in and data_out ) then
		set_data_2B(data_in)
		set_run_get_cmd("PBJE_FULL_SCAN")
		data_out = dict.jtag("GET_8B_DATA")
--		if numbits <= 6*8 then
--			data_out = dict.jtag("GET_8B_DATA")
--		else
--			data_out = dict.jtag("GET_32B_DATA")
--		end

	else
		print("ERROR, bad arguements to jtag scan function")
		return nil
	end

	--currently all scans exit at end of shift
	--state has now shifted to EXIT1
	if( cur_jtag_state == "SHIFT_IR" ) then
		cur_jtag_state = "EXIT1_IR"
	elseif( cur_jtag_state == "SHIFT_DR" ) then
		cur_jtag_state = "EXIT1_DR"
	end

	--TODO only return the number of bits scanned, mask away everything else
	return data_out

end


--similar to scan above, but it doesn't exit SHIFT-DR state so we can call it over and over again
local function scan_hold( numbits, data_in, data_out, debug )

	--check to ensure current state is SHIFT-IR/DR
	if not( cur_jtag_state == "SHIFT_IR" or cur_jtag_state == "SHIFT_DR") then
		print("ERROR, jtag state must be SHIFT-IR/DR in order to scan data in/out")
		return nil
	end


	--TODO analyze numbits to determine if needs to be split into several shorter scans
	--currently all scans exit at end of shift
	set_clk(numbits)
	
	--scan out with TDI high
	if( data_in == "HIGH" and data_out ) then
		set_run_get_cmd("PBJE_TDO_SCAN1_HOLD")
		data_out = dict.jtag("GET_8B_DATA")
--		if numbits <= 6*8 then
--			data_out = dict.jtag("GET_8B_DATA")
--		else
--			data_out = dict.jtag("GET_32B_DATA")
--		end

	--scan out with TDI low
	elseif( data_in == "LOW" and data_out ) then
		set_run_get_cmd("PBJE_TDO_SCAN0_HOLD")
		data_out = dict.jtag("GET_8B_DATA")
--		if numbits <= 6*8 then
--			data_out = dict.jtag("GET_8B_DATA")
--		else
--			data_out = dict.jtag("GET_32B_DATA")
--		end

	--scan in with TDI high
	elseif( data_in == "HIGH" and not data_out ) then
		set_run_get_cmd("PBJE_TDO_SCAN1_HOLD")

	--scan in with TDI low
	elseif( data_in == "LOW" and not data_out ) then
		set_run_get_cmd("PBJE_TDO_SCAN0_HOLD")

	--scan in ignoring TDO
	elseif( data_in and not data_out ) then
		--TODO support more than 16/64bits by calling TDI_SCAN_HOLD
		set_data_2B(data_in)
		set_run_get_cmd("PBJE_TDI_SCAN_HOLD")

	--scan in data and capture scan out
	elseif( data_in and data_out ) then
		set_data_2B(data_in)
		set_run_get_cmd("PBJE_FULL_SCAN_HOLD")
		data_out = dict.jtag("GET_8B_DATA")
	--	if numbits <= 6*8 then
	--		data_out = dict.jtag("GET_8B_DATA")
	--	else
	--		data_out = dict.jtag("GET_32B_DATA")
	--	end

	else
		print("ERROR, bad arguements to jtag scan function")
		return nil
	end

--	--currently all scans exit at end of shift
--	--state has now shifted to EXIT1
--	if( cur_jtag_state == "SHIFT_IR" ) then
--		cur_jtag_state = "EXIT1_IR"
--	elseif( cur_jtag_state == "SHIFT_DR" ) then
--		cur_jtag_state = "EXIT1_DR"
--	end

	--TODO only return the number of bits scanned, mask away everything else
	return data_out

end

local function runtest( state, clks, time, debug )

	--check that state is a stable state
	if( state ~= "IDLE" and state ~= "RESET" and state ~= "PAUSE_DR" and state ~= "PAUSE_IR" ) then
		print("ERROR!  runtest must designate a stable state of IDLE, RESET, PAUSE-DR/IR")
		return nil
	end

	--state arguement is required
	--svf standard dictates this as a sticky value use last passed, IDLE is default
	goto_state(state)


	--currently require some number of TCK clocks to perform test
	set_clk(clks)

	if( state == "RESET") then
		--RESET remains stable with TMS = 1
		set_run_get_cmd("PBJE_CLOCK1")
	else
		--PAUSE & IDLE states remain stable with TMS = 0
		set_run_get_cmd("PBJE_CLOCK0")
	end


	--ensure sufficient time has passed
	--current firmware build for stm32 on inlretro6 consumes 400nsec per TCK & ~1msec between USB transfers
	if( time ) then
		--call sleep function for time number of seconds (support fractions)
		sleep( time )	
	end

	return true

end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
--jtag.wait_pbje_done = wait_pbje_done
pbje.sleep = sleep
pbje.init = init
pbje.goto_state = goto_state
pbje.scan = scan
pbje.scan_hold = scan_hold
pbje.runtest = runtest

-- return the module's table
return pbje
