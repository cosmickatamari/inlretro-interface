
-- create the module's table
local mmc2 = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local buffers = require "scripts.app.buffers"
local time = require "scripts.app.time"
local files = require "scripts.app.files"

-- file constants
local mapname = "MMC2"

-- local functions

local function create_header( file, prgKB, chrKB )

	--write_header( file, prgKB, chrKB, mapper, mirroring )
	nes.write_header( file, prgKB, chrKB, op_buffer[mapname], 0)
end


--disables WRAM, selects Vertical mirroring
--sets up CHR-ROM flash PT0 for DATA, Commands: $5555->$1555  $2AAA->$1AAA 
--sets up PRG-ROM flash DATA: $8000-9FFF, Commands: $5555->D555  $2AAA->$AAAA
--leaves $8000 control reg selected to IRQ value selected so $A000 writes don't affect banking
local function init_mapper( debug )


	--RAM is always enabled..
	
	--set mirroring
	dict.nes("NES_CPU_WR", 0xF000, 0x00)	--bit0: 0-vert 1-horz 


	--For CHR-ROM flash writes, use lower 4KB (PT0) for writting data & upper 4KB (PT1) for commands
	dict.nes("NES_CPU_WR", 0xB000, 0x02)	--4KB @ PPU $0000 -> $2AAA cmd & writes
	dict.nes("NES_CPU_WR", 0xC000, 0x02)	--4KB @ PPU $0000
	dict.nes("NES_CPU_WR", 0xD000, 0x05)	--4KB @ PPU $1000 -> $5555 cmd
	dict.nes("NES_CPU_WR", 0xE000, 0x05)	--4KB @ PPU $1000


	--can use upper 16KB $D555 for $5555 commands
	--need lower bank for $AAAA commands and writes
	dict.nes("NES_CPU_WR", 0xA000, 0x00)	--16KB @ CPU $8000

end


--test the mapper's mirroring modes to verify working properly
--can be used to help identify board: returns true if pass, false if failed
local function mirror_test( debug )

	--put mapper in known state (mirror bits cleared)
	init_mapper() 

	--Vertical
	--dict.nes("NES_CPU_WR", 0xF000, 0x00)	--bit0: 0-vert 1-horz 
	if (nes.detect_mapper_mirroring(false) ~= "VERT") then
		print(mapname, " vert mirror test fail")
		return false
	end

	--Horizontal
	dict.nes("NES_CPU_WR", 0xF000, 0x01)	--bit0: 0-vert 1-horz 
	if (nes.detect_mapper_mirroring(false) ~= "HORZ") then
		print(mapname, " horz mirror test fail")
		return false
	end

	--passed all tests
	if(debug) then print(mapname, " mirror test passed") end
	return true

end

--debug CHR-ROM banking with special CHR-ROM image where first
--byte in bank is set to bank number
local function chr_bank_test()

	print("TESTING CHR-ROM BANKS")

	--address that has different values in different banks
	local addr = 0x0017

	dict.nes("NES_CPU_WR", 0xB000, 0) -- 0FD8 register
	dict.nes("NES_CPU_WR", 0xC000, 0) -- 0FE8 register
	print("BANK 0 @ addr:", dict.nes("NES_PPU_RD", addr))
	dict.nes("NES_CPU_WR", 0xB000, 1) -- 0FD8 register
	dict.nes("NES_CPU_WR", 0xC000, 1) -- 0FE8 register
	print("BANK 1 @ addr:", dict.nes("NES_PPU_RD", addr))
	dict.nes("NES_CPU_WR", 0xB000, 2) -- 0FD8 register
	dict.nes("NES_CPU_WR", 0xC000, 2) -- 0FE8 register
	print("BANK 2 @ addr:", dict.nes("NES_PPU_RD", addr))
	dict.nes("NES_CPU_WR", 0xB000, 3) -- 0FD8 register
	dict.nes("NES_CPU_WR", 0xC000, 3) -- 0FE8 register
	print("BANK 3 @ addr:", dict.nes("NES_PPU_RD", addr))


	dict.nes("NES_CPU_WR", 0xB000, 0) -- 0FD8 register
	dict.nes("NES_CPU_WR", 0xC000, 1) -- 0FE8 register
	dict.nes("NES_CPU_WR", 0xD000, 2) -- 1FD8 register
	dict.nes("NES_CPU_WR", 0xE000, 3) -- 1FE8 register

	print("$0FD7:", dict.nes("NES_PPU_RD", 0x0FE8))

	print("$0017:", dict.nes("NES_PPU_RD", 0x0017))
	print("$0017:", dict.nes("NES_PPU_RD", 0x0017))

	print("$0FD8:", dict.nes("NES_PPU_RD", 0x0FD8))

	print("$0017:", dict.nes("NES_PPU_RD", 0x0017))
	print("$0017:", dict.nes("NES_PPU_RD", 0x0017))

	print("$1FE8:", dict.nes("NES_PPU_RD", 0x1FE8))

	print("$1017:", dict.nes("NES_PPU_RD", 0x1017))
	print("$1017:", dict.nes("NES_PPU_RD", 0x1017))

	print("$1FE8:", dict.nes("NES_PPU_RD", 0x1FD8))

	print("$1017:", dict.nes("NES_PPU_RD", 0x1017))
	print("$1017:", dict.nes("NES_PPU_RD", 0x1017))
end

--read PRG-ROM flash ID
local function prgrom_manf_id( debug )

	init_mapper()

	if debug then print("reading PRG-ROM manf ID") end
	--SOP
	--dict.nes("NES_CPU_WR", 0xFAAA, 0xAA)
	--dict.nes("NES_CPU_WR", 0xF555, 0x55)
	--dict.nes("NES_CPU_WR", 0xFAAA, 0x90)
	--PLCC
	dict.nes("NES_CPU_WR", 0xD555, 0xAA)
	dict.nes("NES_CPU_WR", 0xEAAA, 0x55)
	dict.nes("NES_CPU_WR", 0xD555, 0x90)
	rv = dict.nes("NES_CPU_RD", 0x8000) --0xC2 = MXIC
	if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end
	--rv = dict.nes("NES_CPU_RD", 0x8002) --SOP 0x23/0xAB 512KB top/bottom
					    --SOP 0x51/0x57 256KB top/bottom
					    --SOP 0xD6/0x58 1MB top/bottom
	rv = dict.nes("NES_CPU_RD", 0x8001) --PLCC 0xB5/B6/B7 128-512KB SST
	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end

	--exit software
	dict.nes("NES_CPU_WR", 0x8000, 0xF0)

end

--read CHR-ROM flash ID
local function chrrom_manf_id( debug )

	init_mapper()

	if debug then print("reading CHR-ROM manf ID") end
	--A0-A14 are all directly addressable in CNROM mode
	--and mapper writes don't affect PRG banking
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
	dict.nes("NES_PPU_WR", 0x1555, 0x90)
	rv = dict.nes("NES_PPU_RD", 0x0000)
	if debug then print("attempted read CHR-ROM manf ID:", string.format("%X", rv)) end
	rv = dict.nes("NES_PPU_RD", 0x0001)
	if debug then print("attempted read CHR-ROM prod ID:", string.format("%X", rv)) end

	--exit software
	dict.nes("NES_PPU_WR", 0x8000, 0xF0)

end


--dump the PRG ROM
local function dump_prgrom( file, rom_size_KB, debug )

	--PRG-ROM dump 8KB at a time
	local KB_per_read = 8
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x80	-- $8000

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		--select desired bank(s) to dump
		dict.nes("NES_CPU_WR", 0xA000, read_count)	--8KB @ CPU $8000

		--16 = number of KB to dump per loop
		--0x08 = starting read address A12-15 -> $8000
		--NESCPU_4KB designate mapper independent read of NES CPU address space
		--mapper must be 0-15 to designate A12-15
		--dump.dumptofile( file, 16, 0x08, "NESCPU_4KB", true )
		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_PAGE", false )

		read_count = read_count + 1
	end

end

--dump the CHR ROM
local function dump_chrrom( file, rom_size_KB, debug )

	local KB_per_read = 8	--dump both PT at once
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00	-- $0000

	while ( read_count < num_reads ) do

		if debug then print( "dump CHR part ", read_count, " of ", num_reads) end
		--the bank is half the size of KB per read so must multiply by 2
		dict.nes("NES_CPU_WR", 0xB000, (read_count*2))	--4KB @ PPU $0000
		dict.nes("NES_CPU_WR", 0xC000, (read_count*2))	--4KB @ PPU $0000

		--the bank is half the size of KB per read so must multiply by 2 and add 1 for second 1KB
		dict.nes("NES_CPU_WR", 0xD000, (read_count*2+1))--4KB @ PPU $1000
		dict.nes("NES_CPU_WR", 0xE000, (read_count*2+1))--4KB @ PPU $1000

		--4 = number of KB to dump per loop
		--0x00 = starting read address A10-13 -> $0000
		--mapper must be 0x00 or 0x04-0x3C to designate A10-13
		--	bits 7, 6, 1, & 0 CAN NOT BE SET!
		--	0x04 would designate that A10 is set -> $0400 (the second 1KB PT bank)
		--	0x20 would designate that A13 is set -> $2000 (first name table)
		dump.dumptofile( file, KB_per_read, addr_base, "NESPPU_PAGE", false )

		read_count = read_count + 1
	end

end


--dump the WRAM, assumes the WRAM was enabled/disabled as desired prior to calling
local function dump_wram( file, rom_size_KB, debug )

	local KB_per_read = 8
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x06	-- $6000

	while ( read_count < num_reads ) do

		if debug then print( "dump WRAM part ", read_count, " of ", num_reads) end

		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_4KB", false )

		read_count = read_count + 1
	end

end


--write a single byte to PRG-ROM flash
--PRE: assumes mapper is initialized and bank is selected as prescribed in mapper_init
--REQ: addr must be in the first bank $8000-BFFF
local function wr_prg_flash_byte(addr, value, bank, debug)

	if (addr < 0x8000 or addr > 0xBFFF) then
		print("\n  ERROR! flash write to PRG-ROM", string.format("$%X", addr), "must be $8000-BFFF \n\n")
		return
	end

	--select bank
	dict.nes("NES_CPU_WR", 0xA000, bank)

	--send unlock command and write byte
	--dict.nes("NES_CPU_WR", 0xD555, 0xAA)
	--dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
	--dict.nes("NES_CPU_WR", 0xD555, 0xA0)
	dict.nes("NES_CPU_WR", 0xFAAA, 0xAA)
	dict.nes("NES_CPU_WR", 0xF555, 0x55)
	dict.nes("NES_CPU_WR", 0xFAAA, 0xA0)
	dict.nes("NES_CPU_WR", addr, value)	--if this write was $A000-AFFF it will also corrupt the bank

	--recover bank
	dict.nes("NES_CPU_WR", 0xA000, bank)

	local rv = dict.nes("NES_CPU_RD", addr)

	local i = 0

	while ( rv ~= value ) do
		rv = dict.nes("NES_CPU_RD", addr)
		i = i + 1
	end
	if debug then print(i, "naks, done writing byte.") end

	--TODO handle timeout for problems

	--TODO return pass/fail/info
end


--write a single byte to CHR-ROM flash
--PRE: assumes mapper is initialized and bank is selected as prescribed in mapper_init
--REQ: addr must be in the first 2 banks $0000-0FFF
local function wr_chr_flash_byte(addr, value, bank, debug)

	if (addr < 0x0000 or addr > 0x0FFF) then
		print("\n  ERROR! flash write to CHR-ROM", string.format("$%X", addr), "must be $0000-0FFF \n\n")
		return
	end

	--set bank for unlock command
	dict.nes("NES_CPU_WR", 0xB000, 0x0A)	--4KB @ PPU $0000 -> $2AAA cmd & writes
	dict.nes("NES_CPU_WR", 0xC000, 0x0A)	--4KB @ PPU $0000

	--send unlock command
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
	dict.nes("NES_PPU_WR", 0x1555, 0xA0)

	--select desired bank
	dict.nes("NES_CPU_WR", 0xB000, bank)	--4KB @ PPU $0000 -> $2AAA cmd & writes
	dict.nes("NES_CPU_WR", 0xC000, bank)	--4KB @ PPU $0000

	--write data
	dict.nes("NES_PPU_WR", addr, value)

	local rv = dict.nes("NES_PPU_RD", addr)

	local i = 0

	while ( rv ~= value ) do
		rv = dict.nes("NES_PPU_RD", addr)
		i = i + 1
	end
	if debug then print(i, "naks, done writing byte.") end

	--TODO handle timeout for problems

	--TODO return pass/fail/info
end


--host flash one bank at a time...
--this is controlled from the host side one bank at a time
--but requires mapper specific firmware flashing functions
--there is super slow version commented out that doesn't require mapper specific firmware code
local function flash_prgrom(file, rom_size_KB, debug)

	init_mapper()

	--test some bytes
--	wr_prg_flash_byte(0x8000, 0xA5, 0, true)
--	wr_prg_flash_byte(0xBFFF, 0x5A, 0, true)
--	wr_prg_flash_byte(0x8000, 0x15, 1, true)
--	wr_prg_flash_byte(0xBFFF, 0x1A, 1, true)
--	wr_prg_flash_byte(0x8000, 0xF5, 0xF, true)
--	wr_prg_flash_byte(0xBFFF, 0xFA, 0xF, true)

	print("\nProgramming PRG-ROM flash")


	local base_addr = 0x8000 --writes occur $8000-BFFF
	local bank_size = 8*1024 --MMC2 8KByte per PRG bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata


	while cur_bank < total_banks do

		if (cur_bank %8 == 0) then
			print("writting PRG bank: ", cur_bank, " of ", total_banks-1)
		end

		--select desired bank, needed for first write
		dict.nes("NES_CPU_WR", 0xA000, cur_bank)	--16KB @ CPU $8000
		--set cur_bank for recovery and subsequent bytes
		dict.nes("SET_CUR_BANK", cur_bank) 
		if debug then print("get bank:", dict.nes("GET_CUR_BANK")) end

		--program the entire bank's worth of data

		--[[  This version of the code programs a single byte at a time but doesn't require 
		--	mapper specific functions in the firmware
		print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware mapper specific functions 100% host flash algo:
			--wr_prg_flash_byte(base_addr+byte_num, data, cur_bank, false)   --0.7KBps

			--EASIEST FIRMWARE SPEEDUP: 5x faster, create mapper write byte function:
			--MMC3 function works on FME7 just fine
			dict.nes("MMC4_PRG_SOP_FLASH_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)
			--NEXT STEP: firmware write page/bank function can use function pointer for the function above
			--	this may cause issues with more complex algos
			--	sometimes cur bank is needed 
			--	for this to work, need to have function post conditions meet the preconditions
			--	that way host intervention is only needed for bank controls
			--	Is there a way to allow for double buffering though..?
			--	YES!  just think of the bank as a complete memory
			--	this greatly simplifies things and is exactly where we want to go
			--	This is completed below outside the byte while loop @ 39KBps

			if (verify) then
				readdata = dict.nes("NES_CPU_RD", base_addr+byte_num)
				if readdata ~= data then
					print("ERROR flashing byte number", byte_num, " in bank",cur_bank, " to flash ", data, readdata)
				end
			end

			byte_num = byte_num + 1
		end
		--]]

		--Have the device write a banks worth of data
		--FAST!  but needs firmware specific functions and flash control
		flash.write_file( file, bank_size/1024, "MMC4", "PRGROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")

end


--slow host flash one byte at a time...
--this is controlled from the host side byte by byte making it slow
--but doesn't require specific firmware mapper flashing functions
local function flash_chrrom(file, rom_size_KB, debug)

	init_mapper()

	--test some bytes
	--wr_chr_flash_byte(0x0000, 0xA5, 0, true)
	--wr_chr_flash_byte(0x0FFF, 0x5A, 0, true)
	
	print("\nProgramming CHR-ROM flash")

	local base_addr = 0x0000
	local bank_size = 4*1024 --MMC4 4KByte CHR bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata


	while cur_bank < total_banks do

		if (cur_bank %8 == 0) then
			print("writting CHR bank: ", cur_bank, " of ", total_banks-1)
		end

		--set cur_bank so firmware can select desired bank during the write
		dict.nes("SET_CUR_BANK", cur_bank) 
		if debug then print("get bank:", dict.nes("GET_CUR_BANK")) end

		--program the entire bank's worth of data
		--[[  This version of the code programs a single byte at a time but doesn't require 
		--	mapper specific functions in the firmware
		print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware mapper specific functions 100% host flash algo:
			wr_chr_flash_byte(base_addr+byte_num, data, cur_bank, false)  --0.7KBps
			--EASIEST FIRMWARE SPEEDUP: 5x faster, create mapper write byte function:
			--dict.nes("MMC4_CHR_FLASH_WR", base_addr+byte_num, data) --3.8KBps (5.5x faster than above)
			--FASTEST have the firmware handle flashing a bank's worth of data
			--control the init and banking from the host side

			if (verify) then
				readdata = dict.nes("NES_PPU_RD", base_addr+byte_num)
				if readdata ~= data then
					print("ERROR flashing byte number", byte_num, " in bank",cur_bank, " to flash ", data, readdata)
				end
			end

			byte_num = byte_num + 1
		end
		--]]

		--Have the device write a "banks" worth of data, actually 2x banks of 2KB each
		--FAST!  13sec for 512KB = 39KBps
		flash.write_file( file, bank_size/1024, "MMC4", "CHRROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming CHR-ROM flash")
end


--Cart should be in reset state upon calling this function 
local function process(process_opts, console_opts)
	local test = process_opts["test"]
	local read = process_opts["read"]
	local erase = process_opts["erase"]
	local program = process_opts["program"]
	local verify = process_opts["verify"]
	local dumpfile = process_opts["dump_filename"]
	local flashfile = process_opts["flash_filename"]
	local verifyfile = process_opts["verify_filename"]
	-- MMC4 has RAM capability present in some carts.
	local dumpram = process_opts["dumpram"]
	local ramdumpfile = process_opts["dumpram_filename"]
	local writeram = process_opts["writeram"]
	local ramwritefile = process_opts["writeram_filename"]

	local rv = nil
	local file 
	local prg_size = console_opts["prg_rom_size_kb"]
	local chr_size = console_opts["chr_rom_size_kb"]
	local wram_size = console_opts["wram_size_kb"]

	local filetype = "nes"
	--local filetype = "bin"

--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

--test cart by reading manf/prod ID
	if test then
		print("Testing ", mapname)

		init_mapper()

		--verify mirroring is behaving as expected
		mirror_test(true)

		nes.ppu_ram_sense(0x1000, true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	

		--attempt to read PRG-ROM flash ID
		prgrom_manf_id(true)
		--attempt to read CHR-ROM flash ID
		chrrom_manf_id(true)

		--debug CHR-ROM banking with special CHR-ROM image where first
		--byte in bank is set to bank number
		--chr_bank_test()
	end

--dump the ram to file 
	if dumpram then

		print("\nDumping WRAM...")

		init_mapper()
		
		--SRAM always enabled

		file = assert(io.open(ramdumpfile, "wb"))

		--dump cart into file
		dump_wram(file, wram_size, false)

		--close file
		assert(file:close())

		print("DONE Dumping WRAM")
	end



--dump the cart to dumpfile
	if read then

		print("\nDumping PRG & CHR ROMs...")

		init_mapper()

		file = assert(io.open(dumpfile, "wb"))

		--create header: pass open & empty file & rom sizes
		create_header(file, prg_size, chr_size)

		--dump cart into file
		dump_prgrom(file, prg_size, false)
		dump_chrrom(file, chr_size, false)

		--close file
		assert(file:close())

		print("DONE Dumping PRG & CHR ROMs")
	end


--erase the cart
	if erase then

		print("\nerasing ", mapname)

		init_mapper()

		--PLCC
		print("erasing PRG-ROM PLCC-32");
		dict.nes("NES_CPU_WR", 0xD555, 0xAA)
		dict.nes("NES_CPU_WR", 0xEAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xD555, 0x80)
		dict.nes("NES_CPU_WR", 0xD555, 0xAA)
		dict.nes("NES_CPU_WR", 0xEAAA, 0x55)
		dict.nes("NES_CPU_WR", 0xD555, 0x10)

		--SOP
		--print("erasing PRG-ROM SOP-44 flash takes a couple sec...");
		--dict.nes("NES_CPU_WR", 0xFAAA, 0xAA)
		--dict.nes("NES_CPU_WR", 0xF555, 0x55)
		--dict.nes("NES_CPU_WR", 0xFAAA, 0x80)
		--dict.nes("NES_CPU_WR", 0xFAAA, 0xAA)
		--dict.nes("NES_CPU_WR", 0xF555, 0x55)
		--dict.nes("NES_CPU_WR", 0xFAAA, 0x10)
		rv = dict.nes("NES_CPU_RD", 0x8000)

		local i = 0

		--TODO create some function to pass the read value 
		--that's smart enough to figure out if the board is actually erasing or not
		while ( rv ~= 0xFF ) do
			rv = dict.nes("NES_CPU_RD", 0x8000)
			i = i + 1
		end
		print(i, "naks, done erasing prg.");


		--TODO erase CHR-ROM only if present
		init_mapper()

		print("erasing CHR-ROM");
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
		dict.nes("NES_PPU_WR", 0x1555, 0x80)
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
		dict.nes("NES_PPU_WR", 0x1555, 0x10)
		rv = dict.nes("NES_PPU_RD", 0x0000)

		local i = 0

		--TODO create some function to pass the read value 
		--that's smart enough to figure out if the board is actually erasing or not
		while ( rv ~= 0xFF ) do
			rv = dict.nes("NES_PPU_RD", 0x8000)
			i = i + 1
		end
		print(i, "naks, done erasing chr.");


	end

--write to wram on the cart
	if writeram then

		print("\nWritting to WRAM...")

		init_mapper()
		
		--SRAM always enabled

		file = assert(io.open(ramwritefile, "rb"))

		flash.write_file( file, wram_size, "NOVAR", "PRGRAM", false )

		--close file
		assert(file:close())

		print("DONE Writting WRAM")
	end

--program flashfile to the cart
	if program then

		--open file
		file = assert(io.open(flashfile, "rb"))
		--determine if auto-doubling, deinterleaving, etc, 
		--needs done to make board compatible with rom
		
		if filetype == "nes" then
		--advance past the 16byte header
		--TODO set mirroring bit via ciccom
			local buffsize = 1
			local byte
			local count = 1

			for byte in file:lines(buffsize) do
				local data = string.unpack("B", byte, 1)
				--print(string.format("%X", data))
				count = count + 1
				if count == 17 then break end
			end
		end


		flash_prgrom(file, prg_size, false)
		flash_chrrom(file, chr_size, false)

		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually
		print("\nPost dumping PRG & CHR ROMs...")

		init_mapper()

		file = assert(io.open(verifyfile, "wb"))

		--create header: pass open & empty file & rom sizes
		create_header(file, prg_size, chr_size)

		print("DONE post dumping PRG & CHR ROMs")
		--dump cart into file
		time.start()
		dump_prgrom(file, prg_size, false)
		dump_chrrom(file, chr_size, false)
		time.report(prg_size+chr_size)

		--close file
		assert(file:close())

		--compare the flash file vs post dump file
		if (files.compare( verifyfile, flashfile, true ) ) then
			print("\nSUCCESS! Flash verified")
		else
			print("\n\n\n FAILURE! Flash verification did not match")
		end
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
mmc2.process = process

-- return the module's table
return mmc2
