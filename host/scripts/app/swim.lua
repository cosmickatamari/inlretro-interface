
-- create the module's table
local swim = {}

-- import required modules
local dict = require "scripts.app.dict"
local files = require "scripts.app.files"
local help = require "scripts.app.help"
--local buffers = require "scripts.app.buffers"

-- file constants
-- firmware assembly return error code definitions
--.equ    NO_RESP, 0xFF device didn't appear to respond                              
--.equ    ACK,    0x01  transfer successful
--.equ    NAK,    0x00  device couldn't complete operation                                      
--.equ    HERR,   0x0E  header error
--.equ    PERR,   0x09  pairity error
local ECODE = {}
ECODE.NORESP = 0xFF
ECODE.ACK = 0x01
ECODE.NAK = 0x00
ECODE.PERR = 0x0E
ECODE.HERR = 0x09
--local NRESP = 0xFF
--local ACK = 0x01
--local NAK = 0x00
--local PERR = 0x0E
--local HERR = 0x09

local cur_CSR = 0x00
local SWIM_CSR = 0x7F80
--local DEF_MAX_NAK = 8
local DEF_MAX_NAK = 12	--8 wasn't enough especially for long strings of 0x00 -> 0xff or vice versa

-- local functions
local function get_key_for_value( t, value )
	for k,v in pairs(t) do
		if v==value then 
			return k
		end
	end
	return nil
end

local function system_reset( debug )

	--TODO if cur_CSR has bit 2 set, SWIM must be reactivated 
	
	if dict.swim("SWIM_SRST") ~= ECODE.ACK then
		if debug then print("ERROR unable to reset STM8 core") end
	else
--		print("reset stm8 core")
	end
end

local function reset_swim()
	--print("resetting SWIM")
      	dict.swim("SWIM_RESET")	

--	wotf(SWIM_CSR, cur_CSR)
	--must rewrite current value of SWIM_CSR register as HIGHSPEED is cleared during SWIM RESET
      	dict.swim("WOTF", SWIM_CSR, cur_CSR)	
end


local function rotf(addr, hspeed, debug)

	local result = ECODE.NAK
	local data
	local tries = 5
	local resets = 3

	local opcode = "ROTF"
	if hspeed then
		opcode = "ROTF_HS"
	end

	while result ~= "ACK" and tries > 0 do
		result, data = dict.swim(opcode, addr)
		--convert the value to the key string
		result = get_key_for_value( ECODE, result)
		if debug then print("rotf", string.format(" %X: %X, result ", addr, data), result) end
		if result == "NORESP" then
			reset_swim()
		end
		tries = tries - 1
		if tries == 0 then 
			print("ERROR max tries exceeded") 
			reset_swim()
			resets = resets - 1
			if resets > 0 then
				tries = 5
			end
		end
	end
	
	--return the result of the final transfer
	return result, data
end

local function wotf(addr, data, hspeed, debug, maxnaks)

	local result = ECODE.NAK
	local tries = DEF_MAX_NAK
	local resets = 3

	--allow calling function to increase max allowed NAKs
	if maxnaks then
		tries = maxnaks
	end

	local opcode = "WOTF"
	if hspeed then
		opcode = "WOTF_HS"
	end

	while result ~= "ACK" and tries >= 0 do
		result = dict.swim(opcode, addr, data)
		result = get_key_for_value( ECODE, result)
		if debug then print("wotf", string.format(" %X: %X, result ", addr, data), result) end
		if result == "NORESP" then
			reset_swim()
		end
		tries = tries - 1
		if tries < 0 then 
			print("ERROR max tries exceeded, resetting stm8") 
			reset_swim()
			resets = resets - 1
			if resets > 0 then
				tries = 5
				print("    FAIL! max resets exceeded!!!!!") 
			end
		end
	end

	--return the result of the final transfer
	return result
end

local function stop_and_reset()

	--switch to low speed if was in high
      	dict.swim("SWIM_RESET")	

	--set bit 2 so SWIM module is also reset on system reset
	cur_CSR = 0xA4
--	wotf(SWIM_CSR, cur_CSR)
	--must rewrite current value of SWIM_CSR register as HIGHSPEED is cleared during SWIM RESET
	wotf(SWIM_CSR, cur_CSR)

	--print("resetting SWIM")
      	dict.swim("SWIM_SRST")	
end

local function unlock_eeprom(hspeed)
	--Write 0xAE then 56h in
	--FLASH_DUKR (0x00 5064)(1)(2)
	wotf(0x5064, 0xAE, hspeed) 
	wotf(0x5064, 0x56, hspeed) 
end

local function unlock_flash(hspeed)
	--write 0x56 then 0xae in
	--flash_pukr (0x00 5062)(3)
	wotf(0x5062, 0x56, hspeed) 
	wotf(0x5062, 0xAE, hspeed) 
end

local function fast_flash_mode(hspeed)
	--set to fast flash mode
	--;2. Write 0x10 in FLASH_CR2 (FPRG bit active), and 0xEF in FLASH_NCR2 (NFPRG bit
	--        ;active).
	--        mov     FLASH_CR2, #0x10
	--        mov     FLASH_NCR2, #0xEF
	wotf(0x505B, 0x10, hspeed) 
	wotf(0x505C, 0xEF, hspeed) 
end

local function wait_till_eop_set(hspeed, debug)

	local timeout = 0

	local result, data = rotf(0x505f, hspeed, false )

	while ((data & 0x04) ~= 0x04) do
		result, data = rotf(0x505f, hspeed, false )
		if debug then print("FLASH_IAPSR EOP bit wasn't set, polling again.") end

		timeout = timeout+1

		if (timeout == 20) then
			print("EOP was never set after", timeout, "attempts.  I quit..")
			return
		end
	end
end


local function lock_flash_eeprom(hspeed)
	--lock eeprom:
	--Reset bit 3 (DUL)
	--in FLASH_IAPSR (0x00 505F)
	--lock flash:
        --Reset bit 1 (PUL)
	--in FLASH_IAPSR (0x00 505F)
	--just lock em both
	wotf(0x505F, 0x00, hspeed) 
end

local function swim_test()
	--print("rotf :", string.format("%X  %X", dict.swim("ROTF_HS", 0x8028)))
	--print("wotf :", dict.swim("WOTF_HS", 0x8028, 0x49))
	--print("rotf :", string.format("%X  %X", dict.swim("ROTF_HS", 0x8028)))

--read then write to SRAM
--	print("rotf :", string.format("%X  %X", dict.swim("ROTF_HS", 0x0000)))

      	--print("wotf :", dict.swim("WOTF_HS", 0x0000, 0x00))
	--high speed now, enable flag with true
	rotf(0x0000, true, true) 
	wotf(0x0000, 0x00, true, true) 
	rotf(0x0000, true, true) 
	wotf(0x0000, 0xFF, true, true) 
	rotf(0x0000, true, true) 
	wotf(0x0000, 0xA5, true, true) 
	rotf(0x0000, true, true) 
	wotf(0x0000, 0xC3, true, true) 
	rotf(0x0000, true, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	rotf(0x0000, true) 
--	wotf(0x0000, 0xEE, true) 
--	rotf(0x0000, true) 
--	wotf(0x0000, 0xAA, true) 
--	rotf(0x0000, true) 
--	wotf(0x0000, 0x55, true) 
--	rotf(0x0000, true) 

--	print("rotf :", string.format("%X  %X", dict.swim("ROTF_HS", 0x0000)))

--read then write to eeprom
--	print("rotf :", string.format("%X  %X", dict.swim("ROTF_HS", 0x4000)))
--
--      --need to unlock the eeprom first!
--	unlock_eeprom(true)
----	--Write 0xAE then 56h in
----	--FLASH_DUKR (0x00 5064)(1)(2)
----      	print("wotf :", dict.swim("WOTF_HS", 0x5064, 0xAE))
----      	print("wotf :", dict.swim("WOTF_HS", 0x5064, 0x56))
----	--write data
--	rotf(0x4000, true)
--	wotf(0x4000, 0xDE, true)
--	wotf(0x4001, 0xAD, true)
--	wotf(0x4002, 0xBE, true)
--	wotf(0x4003, 0xEF, true)
----      	print("wotf :", dict.swim("WOTF_HS", 0x4000, 0x00))
----
----	--lock eeprom
----	--Reset bit 3 (DUL)
--	lock_flash_eeprom(true)
----	--in FLASH_IAPSR (0x00 505F)
----      	print("wotf :", dict.swim("WOTF_HS", 0x505F, 0x00))
----
----	print("rotf :", string.format("%X  %X", dict.swim("ROTF_HS", 0x4000)))
--	rotf(0x4000, true)
--	rotf(0x4001, true)
--	rotf(0x4002, true)
--	rotf(0x4003, true)
--
----read then write to flash
----	print("rotf :", string.format("%X  %X", dict.swim("ROTF_HS", 0x8028)))
--
--	--need to unlock the flash first!
--	unlock_flash(true)
--	--write data
--	print("WRITE DATA")
--	local byte_addr = 0x8028
--	local data = 0xFF
--	while byte_addr < 0x8030 do
--		wotf(byte_addr, data, true, true) 
--	
--		byte_addr = byte_addr + 1
----		data = data + 0x11
--
--	end
--	--lock flash/eeprom
--	lock_flash_eeprom(true)
--	--read it back

--	print("READ BACK DATA")
--	local byte_addr = 0x0200
--	while byte_addr < 0x0280 do
--		rotf(byte_addr, true, true)
--	
--		byte_addr = byte_addr + 1
--	end

	--test by blinking LED via periph register access
	--v2 board has LED on hi_lo_sel PA2
--	print("wotf LED PA_CR1:", dict.swim("WOTF", 0x5003, 0xFF))	--default is input w/o pullup, now pullups enabled
--	--LED should be dimly lit
--	--set pin to pushpull
--	print("wotf LED PA_DDR:", dict.swim("WOTF", 0x5002, 0x04))	--PA2 is output CR1 set above makes pushpull
--	--LED is push/pull, ODR default to 0, so LED OFF
--	print("wotf LED PA_ODR:", dict.swim("WOTF", 0x5000, 0x04))	--PA2 output set LED ON!
--	print("wotf LED PA_ODR:", dict.swim("WOTF", 0x5000, 0x00))	--PA2 output set LED OFF!
--HIGH SPEED
--	print("wotf LED PA_CR1:", dict.swim("WOTF_HS", 0x5003, 0xFF))	--default is input w/o pullup, now pullups enabled
--	--LED should be dimly lit
--	--set pin to pushpull
--	print("wotf LED PA_DDR:", dict.swim("WOTF_HS", 0x5002, 0x04))	--PA2 is output CR1 set above makes pushpull
--	--LED is push/pull, ODR default to 0, so LED OFF
--	print("wotf LED PA_ODR:", dict.swim("WOTF_HS", 0x5000, 0x04))	--PA2 output set LED ON!
--	print("wotf LED PA_ODR:", dict.swim("WOTF_HS", 0x5000, 0x00))	--PA2 output set LED OFF!


	--holds SWIM pin low for 16usec+ to reset SWIM comms incase of error
--	dict.swim("SWIM_RESET")	

	--reset the chip, if bit2 set in CSR the SWIM exits active mode with this reset
--	print("wotf SRST:", dict.swim("SWIM_SRST"))	
	--SWIM is now inactive chip is executing it's program code

	--indicate to logic analyzer that test sequence above is complete
--	dict.pinport("CTL_SET_LO", "EXP0")
--	dict.io("IO_RESET")	

end


local function read_stack()

	--STM8 stack starts at $0200 which is where the CIC version 
	--and other special data is placed starting with v2.0
	local stack_start = 0x0200
--	local last_char = 73	--73 end of copyright
	local last_char = 74	--mirroring bit
	local ack
	local data = {}

	--read 
	for i = 0, last_char do 
		ack, data[i+1] = rotf(stack_start+i, true, false) 
	end

	print("\n")

	local j = 1
	while data[j] do
		io.write(string.char(data[j]))
		--io.write("B-",j,"=",data[j], " ")
		j = j+1
	end
	print("\n")

--	print("rotf :", string.format("%X  %X", dict.swim("ROTF_HS", 0x0000)))


end



local function start( debug, noreset )

	--dict.io("IO_RESET")	

	--dict.io("SNES_INIT")	
	--dict.io("SWIM_INIT", "SWIM_ON_EXP0")	
	dict.swim("SWIM_ACTIVATE")	

	--holds SWIM pin low for 16usec+ to reset SWIM comms incase of error
	--also verifies that device has SWIM active
      	dict.swim("SWIM_RESET")	

	--write 0A0h to SWIM_CSR
	--bit 5: allows entire memory range to be read & swim reset to be accessed
	--bit 7: masks internal reset sources (like WDT..?)
	cur_CSR = 0xA0
	if wotf(SWIM_CSR, cur_CSR) == "ACK" then
		if debug then print("Successfully established SWIM comms") end
	else
		print("Unable to establish SWIM comms")
		return false
	end


	--read SWIM_CSR
      	--dict.swim("SWIM_RESET")	

	--print("wotf SRST:", dict.swim("SWIM_SRST"))	
	--print("wotf SWIM_CSR:", dict.swim("WOTF", 0x7F80, 0xA0))	

	--now the SRST command is available, whole memory range available, and internal resets disabled
	--by default there is now a breakpoint set at reset vector
	
	--reset the STM8 core
	dict.swim("SWIM_SRST")
	--optionally reset core below, but not of much use since a ROP enabled device
	--will reset once SWIM comms initiate rotf/wotf
	--if(noreset ~= true) then
	--	if debug then print("RESETTING STM8 CPU") end
	--	system_reset( true )
	--else
	--	if debug then print("STM8 CPU WASN'T reset during activation") end
	--end

	--the STM8 core is now stalled @ reset vector
	--can read/write to any address on STM8 core
	--if CIC ROP bit is set, we can only r/w to periph & SRAM

	--bit 2: SWIM is reset (exits active mode) when chip reset
	--this forces successful SWIM entry on each execution of script
	--TODO if this bit is enabled bunch of other code here needs updated to re-establish SWIM 
	--via this routine when system is reset
--	cur_CSR = cur_CSR | 0x04
--	wotf(SWIM_CSR, cur_CSR)

	--print("switch to HS")
	--bit 4: SWIM HIGH SPEED (set for high speed)  SWIM RESET will set back to low speed
	--print("wotf SWIM_CSR:", dict.swim("WOTF", 0x7F80, 0xB4))	
	cur_CSR = cur_CSR | 0x10
	wotf(SWIM_CSR, cur_CSR)
	
--	swim_test()

	return true
end


local function printCSR()
	print(cur_CSR)
end

local function disable_ROP_erase(debug)

	local toprint = nil-- debug
	local maxnak = 20

	if debug then print("disabling ROP and erasing STM8 CIC") end
	unlock_eeprom(true)

	--FLASH_CR2 and FLASH_NCR2 must be enabled to permit option byte writing
	--DEF_8BIT_REG_AT(FLASH_CR2,0x505b);  default 0x00
	--DEF_8BIT_REG_AT(FLASH_NCR2,0x505c); default 0xFF
	--BIT 7: OPT/NOPT
	if debug then print("enabling optn byte writes") end
	wotf(0x505B, 0x80, true, toprint, maxnak)
	wotf(0x505C, 0x7F, true, toprint, maxnak)

	--enable READ OUT PROTECTION
	--0x4800 Read-out protection (ROP)
	--0x00 by default, set to 0xAA to prevent reading out flash & eeprom
	if debug then print("reading ROP byte") end
	if debug then rotf(0x4800, true, debug) end
	if debug then print("clearing ROP byte") end
	wotf(0x4800, 0x00, true, toprint, maxnak)
	--after clearing ROP, system must be reset
	--getting error that option bytes aren't complimentary
	--seems they get completely erased and we should now flash them
	--to be complimentary
	--go ahead and write proper "erased" complimentary data prior to system reset

	--option bytes seem to take awhile to write, increase max 
	if debug then print("writing compliment option bytes") end
--ROP	wotf(0x4800, 0x00, true, toprint)
	wotf(0x4801, 0x00, true, toprint, maxnak)
	wotf(0x4802, 0xFF, true, toprint, maxnak)
	wotf(0x4803, 0x00, true, toprint, maxnak)
	wotf(0x4804, 0xFF, true, toprint, maxnak)
	wotf(0x4805, 0x00, true, toprint, maxnak)
	wotf(0x4806, 0xFF, true, toprint, maxnak)
	wotf(0x4807, 0x00, true, toprint, maxnak)
	wotf(0x4808, 0xFF, true, toprint, maxnak)
	wotf(0x4809, 0x00, true, toprint, maxnak)
	wotf(0x480A, 0xFF, true, toprint, maxnak)

	--disable option byte writing
	if debug then print("disabling option byte writting") end
	wotf(0x505B, 0x00, true, toprint, maxnak)
	wotf(0x505C, 0xFF, true, toprint, maxnak)

	if debug then print("locking eeprom") end
	lock_flash_eeprom(true)

--	if debug then print("read back option bytes") 
--	rotf(0x4800, true, true)
--	rotf(0x4801, true, true)
--	rotf(0x4802, true, true)
--	rotf(0x4803, true, true)
--	rotf(0x4804, true, true)
--	rotf(0x4805, true, true)
--	rotf(0x4806, true, true)
--	rotf(0x4807, true, true)
--	rotf(0x4808, true, true)
--	rotf(0x4809, true, true)
--	rotf(0x480A, true, true)
--	end

	--need to reset the chip to reload option bytes
	--after clearing ROP, system must be reset
	if debug then print("resetting STM8") end
	system_reset( false )
	--TODO swim may need re-established if SWIM_CSR RST bit is set
--	start()

	if debug then print("done erasing chip, ROP disabled") end
end

local function write_optn_bytes(rop, debug)

	local maxnak = 20
	local toprint = nil--debug
	if debug then print("programming option bytes") end
	unlock_eeprom(true)

	--FLASH_CR2 and FLASH_NCR2 must be enabled to permit option byte writing
	--DEF_8BIT_REG_AT(FLASH_CR2,0x505b);  default 0x00
	--DEF_8BIT_REG_AT(FLASH_NCR2,0x505c); default 0xFF
	--BIT 7: OPT/NOPT
	wotf(0x505B, 0x80, true, toprint, maxnak)
	wotf(0x505C, 0x7F, true, toprint, maxnak)

	--need to enable AFR0 for TIM1 timer input pins
	--AFR0 Alternate function remapping option 0(2)
	--0: AFR0 remapping option inactive: Default alternate functions(1)
	--1: Port C5 alternate function = TIM2_CH1; port C6 alternate function =
	--TIM1_CH1; port C7 alternate function = TIM1_CH2.
	--0x4803 Alternate function remapping (AFR)
	--	 OPT2 AFR7 AFR6 AFR5 AFR4 AFR3 AFR2 AFR1 AFR0 0x00
	--0x4804 NOPT2 NAFR7 NAFR6 NAFR5 NAFR4 NAFR3 NAFR2 NAFR1 NAFR0 0xFF
	if debug then print("ENABLING AFR0 for TIM1") end
	wotf(0x4803, 0x01, true, toprint, maxnak)
	wotf(0x4804, 0xFE, true, toprint, maxnak)
	print("optn byte write enabled")

	--enable READ OUT PROTECTION
	--0x4800 Read-out protection (ROP)
	--0x00 by default, set to 0xAA to prevent reading out flash & eeprom
	if rop then
		wotf(0x4800, 0xAA, true, toprint, maxnak)
		print("Read out Protection enabled")
	else
		print("Read out Protection isn't enabled, CIC code can be stolen!")
	end

	--disable option byte writing
	wotf(0x505B, 0x00, true, toprint, maxnak)
	wotf(0x505C, 0xFF, true, toprint, maxnak)
	print("optn byte write disabled")

	lock_flash_eeprom(true)
	if debug then print("done with option byte programming") end
end

--erase 64Byte blocks starting at addr
--have to call separately for eeprom/flash, addr desides which to unlock
local function erase_blocks(addr, num_blocks, debug)

	--TODO take this arg from calling function
	local hspeed = true

	local block_num = 0
	local readdata = 0
	local readresult = 0

	if addr < 0x8000 then
		unlock_eeprom(true)
	else --flash
		unlock_flash(true)
	end

	if debug then print("SWIM erasing", num_blocks, "* 64Byte blocks starting at:", help.hex(addr)) end

	while (block_num < num_blocks) do


		--enable block erase
		wotf(0x505B, 0x20, hspeed)
		wotf(0x505C, 0xDF, hspeed) 

		--write 0x00 to first 4 bytes of the block
		wotf(addr, 0x00, hspeed) 
		wotf(addr+1, 0x00, hspeed) 
		wotf(addr+2, 0x00, hspeed) 
		wotf(addr+3, 0x00, hspeed) 

		--poll EOP
		wait_till_eop_set(hspeed)

		--next block
		block_num = block_num+1
		addr = addr + 64
	end

end

local function erase_flash(debug)
	erase_blocks(0x8000, 128, true)
end

local function erase_eeprom(debug)

	--TODO take arg of device type, for now assume S003
	--erase_blocks(0x4000, 2, true) --S001/3
	erase_blocks(0x4000, 10, true)--S103
end

local function read_memory(file, addr, num_bytes, debug)

	local toprint = debug
	local buff_size = 1
	local byte_num = 0
	local readdata = 0
	local readresult = 0
	if debug then print("SWIM Dumping", num_bytes, "starting at:", help.hex(addr)) end

	while (byte_num < num_bytes) do
		local toprint = false
		readresult, readdata = rotf(addr+byte_num, true, toprint )
		byte_num = byte_num+1
		files.wr_bin_byte(file, readdata)
	end

end

local function dump_flash(file, debug)
	read_memory(file, 0x8000, 8*1024, true)
end

local function dump_eeprom(file, debug)
	--TODO flag for S001/3 or S103
	--for now just assume 640Bytes like S103
	read_memory(file, 0x4000, 640, true)
end


--takes ~37sec to flash entire 8KB, recommend calling fastblock below if flashing entire chip
local function write_flash(file, debug)

	unlock_flash(true)

	local toprint = debug
	local buff_size = 1
	local byte_num = 0
	local readdata = 0
	local readresult = 0
	print("Programming STM8 CIC flash")
	for byte in file:lines(buff_size) do
		local data = string.unpack("B", byte, 1)
	--	print(data)
		wotf(0x8000+byte_num, data, true, toprint)
		--wotf(0x8000+byte_num, 0xFF, true, true)
		readresult, readdata = rotf(0x8000+byte_num, true, toprint )
		if readdata ~= data then
			print("ERROR flashing byte number", byte_num, "to STM8 CIC", data, readdata)
		end
		--if byte_num == 0x4C0 then
		--if byte_num == 0x020 then
		----if byte_num == 0x1FFF then
		--	return
		--end
		byte_num = byte_num + 1
	end

	print("Done with STM8 CIC flash")
	lock_flash_eeprom(true)
end


--erases then writes 8KByte of STM8 flash
--currently writes entire 8KB of flash, file must be exactly 8KByte
--testing in high speed mode single byte rotf: 5.5sec (same as dump speed)
--flashing the entire chip takes 37 seconds in single byte mode
--does not verify as flashing, recommend dumping and comparing files
local function write_flash_fastblock(file, debug)

	--erase_blocks(0x8000, 128, true)
	erase_flash()

	unlock_flash(true)

	local toprint = debug
	local buff_size = 1
	local byte_num = 0
	local readdata = 0
	local readresult = 0
	print("Programming STM8 CIC flash")

	--for byte in file:lines(buff_size) do
	while (byte_num < 0x2000) do

		--set to fast mode for each block
		fast_flash_mode(true)
		--write 64 bytes, then poll EOP
		local byteinblock = 0

		while byteinblock<64 do

			local byte = file:read(1)
			--local byte = files.rd_bin_byte(file)
			local data = string.unpack("B", byte, 1)
		--	print(data)
			wotf(0x8000+byte_num, data, true, toprint)
			--wotf(0x8000+byte_num, 0xFF, true, true)
		--	readresult, readdata = rotf(0x8000+byte_num, true, toprint )
		--	if readdata ~= data then
		--		print("ERROR flashing byte number", byte_num, "to STM8 CIC", data, readdata)
		--	end
			byte_num = byte_num + 1
			byteinblock = byteinblock + 1
		end

		--poll EOP till it's set
		wait_till_eop_set(true)
	end

	print("Done with STM8 CIC flash")
	lock_flash_eeprom(true)
end

local function snes_v3_prgm(debug)
	--dict.pinport("CTL_IP_PU", "SNES_RST")
	--reset_swim()
--	print("curCSR", cur_CSR)
	--start()
--	print("curCSR", cur_CSR)
	--SNES v3 boards route Flash /OE to STM8 pin 3 PD6

	--(PD_ODR,0x500f);
	--(PD_IDR,0x5010);
	--(PD_DDR,0x5011);
	--(PD_CR1,0x5012);
	--(PD_CR2,0x5013);

	wotf(0x5012, 0x40, true, debug)	--PD6 is input with pullup, if changed to output via DDR it will be push pull
	wotf(0x5011, 0x40, true, debug)	--PD6 is push-pull output now 
	wotf(0x500F, 0x40, true, debug)	--PD6 high, program mode
end

local function snes_v3_play(debug)
	--dict.pinport("CTL_IP_PU", "SNES_RST")
	--reset_swim()
	--start()
	wotf(0x5012, 0x40, true, debug)	--PD6 is input with pullup, if changed to output via DDR it will be push pull
	wotf(0x5011, 0x40, true, debug)	--PD6 is push-pull output now 
	wotf(0x500F, 0x00, true, debug)	--PD6 low, play mode
end

-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
swim.start = start
swim.write_flash = write_flash
swim.write_flash_fastblock = write_flash_fastblock
swim.read_memory = read_memory
swim.dump_flash = dump_flash
swim.dump_eeprom = dump_eeprom
swim.erase_blocks = erase_blocks
swim.erase_flash = erase_flash
swim.erase_eeprom = erase_eeprom
swim.write_optn_bytes = write_optn_bytes
swim.disable_ROP_erase = disable_ROP_erase
swim.printCSR = printCSR
swim.wotf = wotf
swim.rotf = rotf
swim.swim_test = swim_test
swim.read_stack = read_stack
swim.snes_v3_prgm = snes_v3_prgm
swim.snes_v3_play = snes_v3_play
swim.stop_and_reset = stop_and_reset

-- return the module's table
return swim


-- NOTES old code that was once used to flash STM8 CICs from inlretro.lua

			--Check for SWIM on A0
		--[[
			dict.io("IO_RESET")	
			print("start swim")

			dict.io("SWIM_INIT", "SWIM_ON_A0")	
			----[[
			if swim.start(true) then
				--SWIM is now established and running at HIGH SPEED
				snes_swimcart = false	--don't want to use SWIM pin to control flash /OE, use SNES RESET (EXP0) instead

				swim.swim_test()

				--swim.write_optn_bytes( true, true ) -- enable ROP, debug

				--check if ROP set, allow clearing ROP and erasing CIC
				--blindly erase STM8 CIC for now by disabling ROP
				swim.disable_ROP_erase(true)
				
				--open CIC file
				local cic_file = assert(io.open("stm8_8KB_zero.bin", "rb"))
				--local cic_file = assert(io.open("stm8_8KB_0xff.bin", "rb"))
				--local cic_file = assert(io.open("stm8_8KB_testpattern.bin", "rb"))
				--local cic_file = assert(io.open("NESCIC.bin", "rb"))
				--local cic_file = assert(io.open("LIZv1.bin", "rb"))

				--write CIC file
				swim.write_flash( cic_file )

				--close CIC file
				assert(cic_file:close())

				--set ROP & AFR0
				swim.write_optn_bytes( true, true ) -- ROP not set, debug set

				-- reset STM8 CIC and end SWIM comms to it can execute what we just flashed
				swim.stop_and_reset()
			else
				print("ERROR problem with STM8 CIC")
			end

			print("done flashing STM8 on A0")

			dict.io("IO_RESET")	

			--]]
