
-- create the module's table
local ciccom = {}

-- import required modules
local dict = require "scripts.app.dict"
local time = require "scripts.app.time"
local help = require "scripts.app.help"

-- file constants
--local resetpin = "AFL" --v2.0
--local datapin = "GBP" --v2.0
--local resetpin = "SWC" --v2.0N
--local datapin = "FREE" --v2.0N

--SNES v3.3
local resetpin = "AFL" --v2.0
local datapin = "SWC" --v2.0
--TODO move clock pin to a define & have the reset/data defines set based on the device

-- local functions
local function start( debug )

	--need to disable alternate function on SWCLK for STM_NES
	dict.io( "IO_RESET", "DISABLE_STM_DEBUG")

	--CIC reset & clock needs to be low to start
	dict.pinport( "CTL_OP", resetpin)
	dict.pinport( "CTL_SET_LO", resetpin)	--CIC RESET LOW

	dict.pinport( "CTL_OP", datapin)
	dict.pinport( "CTL_SET_LO", datapin)	--INL CIC DATA LOW


--[[
	--reset the stm8 and disable SWIM, to get CIC in known state
	dict.io("SWIM_INIT", "SWIM_ON_A0")	
	if swim.start(true) then
		swim.stop_and_reset()
	else
		print("fail to activate SWIM")
	end

	--now the CIC should be restarting
	--takes ~0.5msec for it to get through boot sequence
	time.sleep(0.01) --10msec to be overly safe
	--after that time it's waiting for a CIC reset pulse to wake it
--]]



	--CIC CLK needs to be low before taking CIC RESET HIGH
	dict.pinport( "ADDR_ENABLE")
	dict.pinport( "ADDR_OP")
	dict.pinport( "ADDR_SET", 0)	--CIC CLK LOW (A0)

	--reset CIC by making it panic
--	dict.pinport( "CTL_SET_HI", "AFL")
--	dict.pinport( "CTL_SET_LO", "AFL")
--	rv = 2000	
--	while rv ~= 0 do 
--		dict.pinport( "ADDR_SET", 1)	--CIC CLK
--		dict.pinport( "ADDR_SET", 0)	--CIC CLK
--		rv = rv -1
--	end


	dict.pinport( "ADDR_SET", 0)	--CIC CLK
	dict.pinport( "CTL_SET_HI", resetpin)
	
	--CIC is now waiting for data to be clocked in using CIC CLK & KEY_DATA_OUT
	--CIC will latch data on rising edges of CLK


	return
end

local function output_bit7(byte, debug)

	if (byte & 0x80 == 0x80) then --output one/high
		if debug then print ("output 1/HI") end
		dict.pinport( "CTL_SET_HI", datapin)
		dict.pinport( "ADDR_SET", 1)	
		dict.pinport( "ADDR_SET", 0)	

	else --output zero/low
		if debug then print ("output 0/LO") end
		dict.pinport( "CTL_SET_LO", datapin)
		dict.pinport( "ADDR_SET", 1)	
		dict.pinport( "ADDR_SET", 0)	
	end
end

local function byte_to_ciccom(byte, debug)

	local cnt = 8

	while cnt > 0 do
		if debug then print("outputting bit7 of:", help.hex(byte)) end
		output_bit7(byte, debug)
		byte = (byte << 1) & 0xFF
		cnt = cnt - 1
	end

end

local function char_to_ciccom( char, debug)
	byte_to_ciccom(string.byte(char), debug)
end

local function set_opcode(opcode)

	--KEY DATA IN is clocked in on rising edges of CIC CLK
	--"M" 0x4D (0b0100_1101 needs to be written to CIC to cause it to toggle mirroring
	--MSbit is latched first

	char_to_ciccom(opcode)


	--now that opcode (ie "M") is written to CIC, end OPCODE write sequence by taking CIC RESET LO
	dict.pinport( "CTL_SET_LO", resetpin)


end


local function write(data, debug)

	--debug = true
	--now send operand "V" (0x56) or "H" (0x48)
	if debug then print("ciccom write is type:", type(data)) end
	if type(data) == 'number' then
		if debug then print("writting number/byte") end
		byte_to_ciccom(data, debug)
	else
		if debug then print("writting character") end
		char_to_ciccom(data, debug)
	end

end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
ciccom.start = start
ciccom.set_opcode = set_opcode
ciccom.write = write
ciccom.byte_to_ciccom = byte_to_ciccom
ciccom.char_to_ciccom = char_to_ciccom
ciccom.wotf = wotf
ciccom.rotf = rotf

-- return the module's table
return ciccom
