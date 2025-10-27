
-- create the module's table
local dualport = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"

-- file constants

-- local functions
local function init_mapper( debug )

	--select bank 0 of flash
	dict.nes("NES_PPU_WR", 0x3FFF, 0x00)
end

local function read_dp(addr)

	dict.pinport("CTL_SET_HI", "M2")
--	dict.pinport("CTL_SET_LO", "ROMSEL")

	dict.pinport("ADDR_SET", addr)
	rv = dict.pinport("DATA_RD")
	print( string.format("%X", rv))

	--disable rom
	--dict.pinport("CTL_SET_HI", "ROMSEL")
	dict.pinport("CTL_SET_HI", "M2")

end

local function write_dp(addr, data)

	--romsel controls /oe
--	dict.pinport("CTL_SET_HI", "ROMSEL")
	--m2 controls /we
	dict.pinport("CTL_SET_LO", "M2")

	dict.pinport("ADDR_SET", addr)
	dict.pinport("DATA_OP")
	dict.pinport("DATA_SET", data)

	--latch data
	dict.pinport("CTL_SET_HI", "M2")

	--leave data bus floating
	dict.pinport("DATA_IP")


end

--read PRG-ROM flash ID
local function prgrom_manf_id( debug )


	--SRAM TEST $2000-3FFF
	--[[
	dict.nes("NES_DUALPORT_WR", 0x2000, 0x00)
	dict.nes("NES_DUALPORT_WR", 0x20AA, 0x00)
	dict.nes("NES_DUALPORT_WR", 0x2055, 0x00)
	dict.nes("NES_DUALPORT_WR", 0x3FFF, 0x00)

	rv = dict.nes("NES_DUALPORT_RD", 0x2000)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x20AA)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x2055)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x3FFF)
	print( string.format("%X", rv))
	
	dict.nes("NES_DUALPORT_WR", 0x2000, 0x55)
	dict.nes("NES_DUALPORT_WR", 0x20AA, 0x55)
	dict.nes("NES_DUALPORT_WR", 0x2055, 0x55)
	dict.nes("NES_DUALPORT_WR", 0x3FFF, 0x55)

	rv = dict.nes("NES_DUALPORT_RD", 0x2000)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x20AA)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x2055)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x3FFF)
	print( string.format("%X", rv))
	
	dict.nes("NES_DUALPORT_WR", 0x2000, 0xDE)
	dict.nes("NES_DUALPORT_WR", 0x20AA, 0xAD)
	dict.nes("NES_DUALPORT_WR", 0x2055, 0xBE)
	dict.nes("NES_DUALPORT_WR", 0x3FFF, 0xEF)

	rv = dict.nes("NES_DUALPORT_RD", 0x2000)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x20AA)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x2055)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x3FFF)
	print( string.format("%X", rv))
	
	dict.nes("NES_DUALPORT_WR", 0x2000, 0x33)
	dict.nes("NES_DUALPORT_WR", 0x3FFF, 0x33)
	dict.nes("NES_DUALPORT_WR", 0x2555, 0x33)
	dict.nes("NES_DUALPORT_WR", 0x3AAA, 0x33)

	rv = dict.nes("NES_DUALPORT_RD", 0x2000)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x3FFF)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x2555)
	print( string.format("%X", rv))
	rv = dict.nes("NES_DUALPORT_RD", 0x3AAA)
	print( string.format("%X", rv))
	--]]


	dict.nes("NES_DUALPORT_WR", 0x0AAA, 0xAA)
	dict.nes("NES_DUALPORT_WR", 0x0555, 0x55)
	dict.nes("NES_DUALPORT_WR", 0x0AAA, 0x90)
	rv = dict.nes("NES_DUALPORT_RD", 0x0000)
	if debug then print("attempted read DP PRG-ROM manf ID:", string.format("%X", rv)) end	--0x01
	rv = dict.nes("NES_DUALPORT_RD", 0x0002)
	if debug then print("attempted read DP PRG-ROM prod ID:", string.format("%X", rv)) end	--0xDA(top), 0x5B(bot)

	--exit software mode
	dict.nes("NES_DUALPORT_WR", 0x0000, 0x90)

end

--[[
local function wr_flash_byte(addr, value, debug)

	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xA0)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", addr, value)

	local rv = dict.nes("NES_CPU_RD", addr)

	local i = 0

	while ( rv ~= value ) do
		rv = dict.nes("NES_CPU_RD", addr)
		i = i + 1
	end
	if debug then print(i, "naks, done writing byte.") end
end
--]]

--Cart should be in reset state upon calling this function 
--this function processes all user requests for this specific board/mapper
local function process(process_opts, console_opts)
	local test = process_opts["test"]
	local read = process_opts["read"]
	local erase = process_opts["erase"]
	local program = process_opts["program"]
	local verify = process_opts["verify"]
	local dumpfile = process_opts["dump_filename"]
	local flashfile = process_opts["flash_filename"]
	local verifyfile = process_opts["verify_filename"]
	
	local rv = nil
	local file 
	-- TODO: Handle variable rom sizes.

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

--test cart by reading manf/prod ID
	if test then
		nes.detect_mapper_mirroring(true)
		nes.ciramce_inv_ppuA13(true)
	--	nes.ppu_ram_sense(0x1000, true)
	--	print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	

		--prgrom_manf_id( true )
		
		rv = dict.nes("EMULATE_NES_CPU_RD", 0x8000)
		print("read:", string.format("%X", rv))
		rv = dict.nes("EMULATE_NES_CPU_RD", 0x8001)
		print("read:", string.format("%X", rv))

		rv = dict.nes("NES_CPU_RD", 0x8000)
		print("read:", string.format("%X", rv))
		rv = dict.nes("NES_CPU_RD", 0x8001)
		print("read:", string.format("%X", rv))

		rv = dict.nes("NES_PPU_RD", 0x0000)
		print("read:", string.format("%X", rv))
		rv = dict.nes("NES_PPU_RD", 0x0000)
		print("read:", string.format("%X", rv))

		--[[
		--read some bytes to verify banking worked
		dict.nes("NES_PPU_WR", 0x3FFF, 0x00)
		rv = dict.nes("NES_DUALPORT_RD", 0x0000)
		print("read:", string.format("%X", rv))
		dict.nes("NES_PPU_WR", 0x3FFF, 0x01)
		rv = dict.nes("NES_DUALPORT_RD", 0x0000)
		print("read:", string.format("%X", rv))
		dict.nes("NES_PPU_WR", 0x3FFF, 0x02)
		rv = dict.nes("NES_DUALPORT_RD", 0x0000)
		print("read:", string.format("%X", rv))
		dict.nes("NES_PPU_WR", 0x3FFF, 0x03)
		rv = dict.nes("NES_DUALPORT_RD", 0x0000)
		print("read:", string.format("%X", rv))
		dict.nes("NES_PPU_WR", 0x3FFF, 0x04)
		rv = dict.nes("NES_DUALPORT_RD", 0x0000)
		print("read:", string.format("%X", rv))
		dict.nes("NES_PPU_WR", 0x3FFF, 0x05)
		rv = dict.nes("NES_DUALPORT_RD", 0x0000)
		print("read:", string.format("%X", rv))
		--]]

	end

--dump the cart to dumpfile
	if read then
		file = assert(io.open(dumpfile, "wb"))

		--dump cart into file
		dump.dumptofile( file, 64, "DPROM", "CHRROM", true )

		--close file
		assert(file:close())
	end


--erase the cart
	if erase then

		init_mapper()

		print("\nerasing DUALPORT ROM");
		--A0-A14 are all directly addressable in CNROM mode
		--only A0-A11 are required to be valid for tsop-48
		--and mapper writes don't affect PRG banking
		dict.nes("NES_DUALPORT_WR", 0x8AAA, 0xAA)
		dict.nes("NES_DUALPORT_WR", 0x8555, 0x55)
		dict.nes("NES_DUALPORT_WR", 0x8AAA, 0x80)
		dict.nes("NES_DUALPORT_WR", 0x8AAA, 0xAA)
		dict.nes("NES_DUALPORT_WR", 0x8555, 0x55)
		dict.nes("NES_DUALPORT_WR", 0x8AAA, 0x10)
		rv = dict.nes("NES_DUALPORT_RD", 0x8000)

		local i = 0

		--TODO create some function to pass the read value 
		--that's smart enough to figure out if the board is actually erasing or not
		while ( rv ~= 0xFF ) do
			rv = dict.nes("NES_DUALPORT_RD", 0x8000)
			i = i + 1
		end
		print(i, "naks, done erasing flash");

	end


--program flashfile to the cart
	if program then

		--open file
		file = assert(io.open(flashfile, "rb"))

		--flash cart
		flash.write_file( file, 64, "DPROM", "CHRROM", true )
		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		dump.dumptofile( file, 64, "DPROM", "CHRROM", true )

		--close file
		assert(file:close())
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
dualport.process = process

-- return the module's table
return dualport
