
-- create the module's table
local action53 = {}

-- import required modules
local nes = require "scripts.app.nes"
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local buffers = require "scripts.app.buffers"

-- file constants
local mapname = "A53"

-- local functions

local function create_header( file, prgKB, chrKB )

	--write_header( file, prgKB, chrKB, mapper, mirroring )
	nes.write_header( file, prgKB, 0, op_buffer[mapname], 0)
end


--local function wr_flash_byte(addr, value, debug)

--base is the actual NES CPU address, not the rom offset (ie $FFF0, not $7FF0)
--local function wr_bank_table(base, entries)
--Action53 not susceptible to bus conflicts, no banktable needed



--initialize mapper for dump/flash routines
local function init_mapper( debug )
	
	--//Setup as CNROM, then scroll through outer banks.
	--cpu_wr(0x5000, 0x80);   //reg select mode
	dict.nes("NES_CPU_WR", 0x5000, 0x80)

	--//   xxSSPPMM   SS-size: 0-32KB, PP-prg mode: 0,1 32KB, MM-mirror
	--cpu_wr(0x8000, 0b00000000);     //reg value 256KB inner, 32KB banks
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	--cpu_wr(0x5000, 0x81);   //outer reg select mode
	dict.nes("NES_CPU_WR", 0x5000, 0x81)
	--cpu_wr(0x8000, 0x00);   //first 32KB bank
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	--
	--cpu_wr(0x5000, 0x01);   //inner prg reg select
	dict.nes("NES_CPU_WR", 0x5000, 0x01)
	--cpu_wr(0x8000, 0x00);   //controls nothing in this size
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	--cpu_wr(0x5000, 0x00);   //chr reg select
	dict.nes("NES_CPU_WR", 0x5000, 0x00)
	--cpu_wr(0x8000, 0x00);   //first chr bank
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	--selecting CNROM means that mapper writes to $8000-FFFF will only change the CHR-RAM bank which
	--doesn't affect anything we're concerned about

end


--read PRG-ROM flash ID
local function prgrom_manf_id( debug )

	init_mapper()

	if debug then print("reading PRG-ROM manf ID") end
	--A0-A14 are all directly addressable in CNROM mode
	--and mapper writes don't affect PRG banking
	dict.nes("NES_CPU_WR", 0xD555, 0xAA)
	dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
	dict.nes("NES_CPU_WR", 0xD555, 0x90)
	rv = dict.nes("NES_CPU_RD", 0x8000)
	if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end
	rv = dict.nes("NES_CPU_RD", 0x8001)
	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end

	--exit software
	dict.nes("NES_CPU_WR", 0x8000, 0xF0)

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
	local prg_size = console_opts["prg_rom_size_kb"]
	local chr_size = console_opts["chr_rom_size_kb"]
	local wram_size = console_opts["wram_size_kb"]

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")


--test cart by reading manf/prod ID
	if test then
		prgrom_manf_id(true)
	end


--dump the cart to dumpfile
	if read then
		--initialize the mapper for dumping
		init_mapper(debug)

		file = assert(io.open(dumpfile, "wb"))

		--create header: pass open & empty file & rom sizes
		create_header(file, prg_size, chr_size)

		--dump cart into file
		dump.dumptofile( file, prg_size, "A53", "PRGROM", true )

		--close file
		assert(file:close())
	end

--erase the cart
	if erase then

		--initialize the mapper for erasing
		init_mapper(debug)

		print("\nerasing action53");

		print("erasing PRG-ROM");
		--A0-A14 are all directly addressable in CNROM mode
		--and mapper writes don't affect PRG banking
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

	end


--program flashfile to the cart
	if program then

		--initialize the mapper for dumping
		init_mapper(debug)

		--open file
		file = assert(io.open(flashfile, "rb"))
		--determine if auto-doubling, deinterleaving, etc, 
		--needs done to make board compatible with rom

		--not susceptible to bus conflicts

		--flash cart
		flash.write_file( file, 512, "A53", "PRGROM", true )
		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually

		--initialize the mapper for dumping
		init_mapper(debug)

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		dump.dumptofile( file, 512, "A53", "PRGROM", true )

		--close file
		assert(file:close())
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
action53.process = process

-- return the module's table
return action53
