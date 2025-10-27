
-- create the module's table
local cninja = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"

-- file constants

-- local functions
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

--base is the actual NES CPU address, not the rom offset (ie $FFF0, not $7FF0)
local function wr_bank_table(base, entries)

	--CNINJA needs to have a bank table present in each and every bank
	--it should also be at the same location in every bank
	--Perhaps it's possible to squeak by with only having it in the first bank as mojontales does..
	
	--doesn't actually matter what bank this gets written to, lets ensure we can get to bank zero
	wr_flash_byte(0x800C, 0x00)

	--select first bank relying on 0 to override 1 for bus conflict
	dict.nes("NES_CPU_WR", 0x800C, 0x00)

	--write bank table to selected bank
	local i = 0
	while( i < entries) do
		wr_flash_byte(base+i, i)
		i = i+1;
	end


	--need a zero value in each bank to get back to first bank
	wr_flash_byte(0x800C, 0x00)	--first bank

	--now place one in all the other banks
	--first swap to next bank
	i = 1
	while( i < 16) do	--16 banks total for 512KByte
		dict.nes("NES_CPU_WR", 0x0000, 0x00)	--select first bank
		dict.nes("NES_CPU_WR", base+i, i)	--jump to next bank
		wr_flash_byte(0x800C, 0x00)		--write zero byte
		i = i + 1
	end
	

end

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
	-- TODO: Support variable ROM sizes.

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

--test cart by reading manf/prod ID
	if test then
		nes.detect_mapper_mirroring(true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	

		-- doesn't work for cninja
		--nes.read_flashID_prgrom_exp0(true)

		--enter software mode
		--CDREAMS connects CHR-ROM A13-16 to mapper bits 4-8
		--so need to set mapper register bits 4 & 5 properly to send unlock commands
		--A13 needs to be low to address CHR-ROM
		--	    15 14 13 12
		-- 0x5 = 0b  0  1  0  1	-> bank:0x20 $1555
		-- 0x2 = 0b  0  0  1  0	-> bank:0x10 $0AAA

		--TODO find bank table prior to doing this
		--or write to mapper without enabling PRG-ROM via exp0
		--tried DISCRETE_EXP0_MAPPER_WR function but didn't work...
		dict.nes("NES_CPU_WR", 0x8000, 0x20)
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)

		dict.nes("NES_CPU_WR", 0x8000, 0x10)
		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)

		dict.nes("NES_CPU_WR", 0x8000, 0x20)
		dict.nes("NES_PPU_WR", 0x1555, 0x90)

		--read manf ID
		rv = dict.nes("NES_PPU_RD", 0x0000)
		if debug then print("attempted read CHR-ROM manf ID:", string.format("%X", rv)) end

		--read prod ID
		rv = dict.nes("NES_PPU_RD", 0x0001)
		if debug then print("attempted read CHR-ROM prod ID:", string.format("%X", rv)) end

		--exit software
		dict.nes("NES_PPU_WR", 0x0000, 0xF0)


		--color ninja mapper has flash enable at $6000-7FFF which has to be 0xA5
--		dict.nes("NES_CPU_WR", 0x6000, 0xA5)
--		not actually needed to ID flash since 32KB banks

		--now can write in flash mode
		dict.nes("NES_CPU_WR", 0xD555, 0xAA)
		dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xD555, 0x90)
		rv = dict.nes("NES_CPU_RD", 0x8000)
		if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end

		--read prod ID
		rv = dict.nes("NES_CPU_RD", 0x8001)
		if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end

		--exit software
		dict.nes("NES_CPU_WR", 0x8000, 0xF0)
		--exit flash mode
--		dict.nes("NES_CPU_WR", 0x6000, 0x00)	--any value besides 0xA5
	end

--dump the cart to dumpfile
	if read then
		file = assert(io.open(dumpfile, "wb"))

		dict.nes("NES_CPU_WR", 0x6000, 0x00)	--any value besides 0xA5

		--TODO find bank table to avoid bus conflicts!
		--dump cart into file
		--dump.dumptofile( file, 128, "CNINJA", "PRGROM", true )
		dump.dumptofile( file, 128, "CDREAM", "PRGROM", true )
		dump.dumptofile( file, 128, "CDREAM", "CHRROM", true )

		--close file
		assert(file:close())
	end


--erase the cart
	if erase then

		print("\nerasing CNINJA");

		print("erasing PRG-ROM");
		--dict.nes("NES_CPU_WR", 0x6000, 0xA5)
		dict.nes("NES_CPU_WR", 0xD555, 0xAA)
		dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xD555, 0x80)
		dict.nes("NES_CPU_WR", 0xD555, 0xAA)
		dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xD555, 0x10)
		rv = dict.nes("NES_CPU_RD", 0x8000)

		local i = 0

		--TODO create some function to pass the read value 
		--that's smart enough to figure out if the board is actually erasing or not
		while ( rv ~= 0xFF ) do
			rv = dict.nes("NES_CPU_RD", 0x8000)
			i = i + 1
		end
		print(i, "naks, done erasing prg.");


		print("erasing CHR-ROM");
		dict.nes("NES_CPU_WR", 0x8000, 0x20)
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)

		dict.nes("NES_CPU_WR", 0x8000, 0x10)
		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)

		dict.nes("NES_CPU_WR", 0x8000, 0x20)
		dict.nes("NES_PPU_WR", 0x1555, 0x80)

		dict.nes("NES_CPU_WR", 0x8000, 0x20)
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)

		dict.nes("NES_CPU_WR", 0x8000, 0x10)
		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)

		dict.nes("NES_CPU_WR", 0x8000, 0x20)
		dict.nes("NES_PPU_WR", 0x1555, 0x10)

		rv = dict.nes("NES_PPU_RD", 0x0000)

		i = 0
		while ( rv ~= 0xFF ) do
			rv = dict.nes("NES_PPU_RD", 0x0000)
			i = i + 1
		end
		print(i, "naks, done erasing chr.\n");
	end


--program flashfile to the cart
	if program then
		--open file
		file = assert(io.open(flashfile, "rb"))
		--determine if auto-doubling, deinterleaving, etc, 
		--needs done to make board compatible with rom

		--no bank table due to no bus conflicts

		--flash cart
		dict.nes("NES_CPU_WR", 0x6000, 0xA5)	--flash write enable
		flash.write_file( file, 128, "CNINJA", "PRGROM", true )
		dict.nes("NES_CPU_WR", 0x6000, 0x00)	--any value besides 0xA5
		flash.write_file( file, 128, "CDREAM", "CHRROM", true )
		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually

		file = assert(io.open(verifyfile, "wb"))

		dict.nes("NES_CPU_WR", 0x6000, 0x00)	--any value besides 0xAA

		--TODO find bank table to avoid bus conflicts!
		--dump cart into file
		--dump.dumptofile( file, 128, "CNINJA", "PRGROM", true )
		dump.dumptofile( file, 128, "CDREAM", "PRGROM", true )
		dump.dumptofile( file, 128, "CDREAM", "CHRROM", true )

		--close file
		assert(file:close())
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
cninja.process = process

-- return the module's table
return cninja
