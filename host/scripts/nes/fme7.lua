
-- create the module's table
local fme7 = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local buffers = require "scripts.app.buffers"

-- file constants
local mapname = "FME7"

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


	--for save data safety start by disable WRAM, and map PRG-ROM to $6000
	dict.nes("NES_CPU_WR", 0x8000, 0x08)
	dict.nes("NES_CPU_WR", 0xA000, 0x00)	--RAM disabled, ROM first bank mapped to $6000
	
	--set mirroring
	dict.nes("NES_CPU_WR", 0x8000, 0x0C)
	dict.nes("NES_CPU_WR", 0xA000, 0x00)	--00-vert 01-horz 10-NT0 11-NT1

	--Bank $0 - PPU $0000-$03FF
	--Bank $1 - PPU $0400-$07FF
	--Bank $2 - PPU $0800-$0BFF
	--Bank $3 - PPU $0C00-$0FFF
	--Bank $4 - PPU $1000-$13FF
	--Bank $5 - PPU $1400-$17FF
	--Bank $6 - PPU $1800-$1BFF
	--Bank $7 - PPU $1C00-$1FFF

	--For CHR-ROM flash writes, use lower 4KB (PT0) for writting data & upper 4KB (PT1) for commands
	dict.nes("NES_CPU_WR", 0x8000, 0x00)
	dict.nes("NES_CPU_WR", 0xA000, 0x00)	--1KB @ PPU $0000

	dict.nes("NES_CPU_WR", 0x8000, 0x01)
	dict.nes("NES_CPU_WR", 0xA000, 0x01)	--1KB @ PPU $0400

	dict.nes("NES_CPU_WR", 0x8000, 0x02)
	dict.nes("NES_CPU_WR", 0xA000, 0x02)	--1KB @ PPU $0800

	dict.nes("NES_CPU_WR", 0x8000, 0x03)
	dict.nes("NES_CPU_WR", 0xA000, 0x03)	--1KB @ PPU $0C00

	--use lower half of PT1 for $5555 commands
	dict.nes("NES_CPU_WR", 0x8000, 0x04)
	dict.nes("NES_CPU_WR", 0xA000, 0x15)	--1KB @ PPU $1000
	
	dict.nes("NES_CPU_WR", 0x8000, 0x05)
	dict.nes("NES_CPU_WR", 0xA000, 0x15)	--1KB @ PPU $1400

	--use upper half of PT1 for $2AAA commands
	dict.nes("NES_CPU_WR", 0x8000, 0x06)
	dict.nes("NES_CPU_WR", 0xA000, 0x0A)	--1KB @ PPU $1800

	dict.nes("NES_CPU_WR", 0x8000, 0x07)
	dict.nes("NES_CPU_WR", 0xA000, 0x0A)	--1KB @ PPU $1C00


	--For PRG-ROM flash writes:
	--mode 0: $C000-FFFF fixed to last 16KByte
	--        reg6 controls $8000-9FFF ($C000-DFFF in mode 1)
	--        reg7 controls $A000-BFFF (regardless of mode)
	--Don't want to write data to $8000-9FFF because those are the bank regs
	--Writting data to $A000-BFFF is okay as that will only affect mirroring and WRAM ctl
	
	--$5555 commands can be written to $D555 (A14 set, A13 clear)
	--$2AAA commands must be written through reg6/7 ($8000-BFFF) to clear A14 & set A13
	--	reg7 ($A000-BFFF) is ideal because it won't affect banking, just mirror/WRAM
	--	actually $2AAA is even, so it'll only affect mirroring which is ideal
	--DATA writes can occur at $8000-9FFF, but care must be taken to maintain banking.
	--	Setting $8000 to a CHR bank prevents DATA writes from changing PRG banks
	--	The DATA write will change the bank select if it's written to an even address though
	--	To cover this, simply select the CHR bank again with $8000 reg after the data write
	--	Those DATA writes can also corrupt the PRG/CHR modes, so just always follow
	--	DATA writes by writting 0x00 to $8000

	--$5555 commands written to $D555
	--$2AAA commands written to $AAAA
	dict.nes("NES_CPU_WR", 0x8000, 0x0A)
	dict.nes("NES_CPU_WR", 0xA000, 0x01)	--8KB @ CPU $A000
	dict.nes("NES_CPU_WR", 0x8000, 0x0B)
	dict.nes("NES_CPU_WR", 0xA000, 0x02)	--8KB @ CPU $C000

	--DATA writes written to $8000-9FFF
	dict.nes("NES_CPU_WR", 0x8000, 0x09)
	dict.nes("NES_CPU_WR", 0xA000, 0x00)	--8KB @ CPU $8000

	--dict.nes("NES_CPU_WR", 0x8000, 0x08)
	--dict.nes("NES_CPU_WR", 0xA000, 0x00)	--8KB @ CPU $6000

	--set $8000 bank select register to IRQ ctl reg so $A000 writes don't change banking
	dict.nes("NES_CPU_WR", 0x8000, 0x0E)

end


--test the mapper's mirroring modes to verify working properly
--can be used to help identify board: returns true if pass, false if failed
local function mirror_test( debug )

	--put mapper in known state (mirror bits cleared)
	init_mapper() 

	--Vertical
	dict.nes("NES_CPU_WR", 0x8000, 0x0C)
	dict.nes("NES_CPU_WR", 0xA000, 0x00)	--00-vert 01-horz 10-NT0 11-NT1
	if (nes.detect_mapper_mirroring(false) ~= "VERT") then
		print(mapname, " vert mirror test fail")
		return false
	end

	--Horizontal
	dict.nes("NES_CPU_WR", 0x8000, 0x0C)
	dict.nes("NES_CPU_WR", 0xA000, 0x01)	--00-vert 01-horz 10-NT0 11-NT1
	if (nes.detect_mapper_mirroring(false) ~= "HORZ") then
		print(mapname, " horz mirror test fail")
		return false
	end

	--NT0
	dict.nes("NES_CPU_WR", 0x8000, 0x0C)
	dict.nes("NES_CPU_WR", 0xA000, 0x02)	--00-vert 01-horz 10-NT0 11-NT1
	if (nes.detect_mapper_mirroring(false) ~= "1SCNA") then
		print(mapname, " NT0 mirror test fail")
		return false
	end

	--NT1
	dict.nes("NES_CPU_WR", 0x8000, 0x0C)
	dict.nes("NES_CPU_WR", 0xA000, 0x03)	--00-vert 01-horz 10-NT0 11-NT1
	if (nes.detect_mapper_mirroring(false) ~= "1SCNB") then
		print(mapname, " NT1 mirror test fail")
		return false
	end

	--passed all tests
	if(debug) then print(mapname, " mirror test passed") end
	return true
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

--read CHR-ROM flash ID
local function chrrom_manf_id( debug )

	init_mapper()

	if debug then print("reading CHR-ROM manf ID") end
	--A0-A14 are all directly addressable in CNROM mode
	--and mapper writes don't affect PRG banking
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x1AAA, 0x55)
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

	--PRG-ROM dump 16KB at a time through FME7 reg9&A
	local KB_per_read = 16
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x08	-- $8000

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		--select desired bank(s) to dump
		dict.nes("NES_CPU_WR", 0x8000, 0x09)
		--the bank is half the size of KB per read so must multiply by 2
		dict.nes("NES_CPU_WR", 0xA000, read_count*2)	--8KB @ CPU $8000

		dict.nes("NES_CPU_WR", 0x8000, 0x0A)
		--the bank is half the size of KB per read so must multiply by 2 and add 1 for second 8KB
		dict.nes("NES_CPU_WR", 0xA000, read_count*2+1)	--8KB @ CPU $A000

		--16 = number of KB to dump per loop
		--0x08 = starting read address A12-15 -> $8000
		--NESCPU_4KB designate mapper independent read of NES CPU address space
		--mapper must be 0-15 to designate A12-15
		--dump.dumptofile( file, 16, 0x08, "NESCPU_4KB", true )
		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_4KB", false )

		read_count = read_count + 1
	end

end

--dump the CHR ROM
local function dump_chrrom( file, rom_size_KB, debug )

	local KB_per_read = 2	--dump one half PT at a time so only need 2 reg writes
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00	-- $0000

	while ( read_count < num_reads ) do

		if debug then print( "dump CHR part ", read_count, " of ", num_reads) end
		dict.nes("NES_CPU_WR", 0x8000, 0x00)
		--the bank is half the size of KB per read so must multiply by 2
		dict.nes("NES_CPU_WR", 0xA000, (read_count*2))	--1KB @ PPU $0000

		dict.nes("NES_CPU_WR", 0x8000, 0x01)
		--the bank is half the size of KB per read so must multiply by 2 and add 1 for second 1KB
		dict.nes("NES_CPU_WR", 0xA000, (read_count*2+1))--1KB @ PPU $0800

		--4 = number of KB to dump per loop
		--0x00 = starting read address A10-13 -> $0000
		--mapper must be 0x00 or 0x04-0x3C to designate A10-13
		--	bits 7, 6, 1, & 0 CAN NOT BE SET!
		--	0x04 would designate that A10 is set -> $0400 (the second 1KB PT bank)
		--	0x20 would designate that A13 is set -> $2000 (first name table)
		dump.dumptofile( file, KB_per_read, addr_base, "NESPPU_1KB", false )

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
--REQ: addr must be in the first bank $8000-9FFF
local function wr_prg_flash_byte(addr, value, debug)

	if (addr < 0x8000 or addr > 0x9FFF) then
		print("\n  ERROR! flash write to PRG-ROM", string.format("$%X", addr), "must be $8000-9FFF \n\n")
		return
	end

	--send unlock command and write byte
	dict.nes("NES_CPU_WR", 0xD555, 0xAA)
	dict.nes("NES_CPU_WR", 0xAAAA, 0x55)
	dict.nes("NES_CPU_WR", 0xD555, 0xA0)
	dict.nes("NES_CPU_WR", addr, value)

	--recover by setting $8000 reg select back to a IRQ reg
	dict.nes("NES_CPU_WR", 0x8000, 0x0E)

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
local function wr_chr_flash_byte(addr, value, debug)

	if (addr < 0x0000 or addr > 0x0FFF) then
		print("\n  ERROR! flash write to CHR-ROM", string.format("$%X", addr), "must be $0000-0FFF \n\n")
		return
	end

	--send unlock command and write byte
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x1AAA, 0x55)
	dict.nes("NES_PPU_WR", 0x1555, 0xA0)
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
	--wr_prg_flash_byte(0x0000, 0xA5, true)
	--wr_prg_flash_byte(0x0FFF, 0x5A, true)

	print("\nProgramming PRG-ROM flash")


	local base_addr = 0x8000 --writes occur $8000-9FFF
	local bank_size = 8*1024 --FME7 8KByte per PRG bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata


	while cur_bank < total_banks do

		if (cur_bank %8 == 0) then
			print("writting PRG bank: ", cur_bank, " of ", total_banks-1)
		end

		--write the current bank to the mapper register
		--DATA writes written to $8000-9FFF
		dict.nes("NES_CPU_WR", 0x8000, 0x09)
		dict.nes("NES_CPU_WR", 0xA000, cur_bank)	--8KB @ CPU $8000

		--set $8000 bank select back to a IRQ register
		--keeps from having the PRG bank changing when writting data
		dict.nes("NES_CPU_WR", 0x8000, 0x0E)


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
			--wr_prg_flash_byte(base_addr+byte_num, data, false)   --0.7KBps

			--EASIEST FIRMWARE SPEEDUP: 5x faster, create mapper write byte function:
			--MMC3 function works on FME7 just fine
			--dict.nes("MMC3_PRG_FLASH_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)
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
		--FAST!  13sec for 512KB = 39KBps
		--MMC3 functions work perfectly for FME7
		flash.write_file( file, 8, "MMC3", "PRGROM", false )

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
	--wr_chr_flash_byte(0x0000, 0xA5, true)
	--wr_chr_flash_byte(0x0FFF, 0x5A, true)
	
	print("\nProgramming CHR-ROM flash")

	local base_addr = 0x0000
	local bank_size = 4*1024 --FME7 1KByte per lower CHR bank and we're using 4 of them..
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata


	while cur_bank < total_banks do

		if (cur_bank %8 == 0) then
			print("writting CHR bank: ", cur_bank, " of ", total_banks-1)
		end

		--write the current bank to the mapper register
		--DATA writes written to $0000-0FFF
		dict.nes("NES_CPU_WR", 0x8000, 0x00)
		dict.nes("NES_CPU_WR", 0xA000, (cur_bank*4))	--1KB @ PPU $0000
		dict.nes("NES_CPU_WR", 0x8000, 0x01)
		dict.nes("NES_CPU_WR", 0xA000, (cur_bank*4+1))	--1KB @ PPU $0400
		dict.nes("NES_CPU_WR", 0x8000, 0x02)
		dict.nes("NES_CPU_WR", 0xA000, (cur_bank*4+2))	--1KB @ PPU $0800
		dict.nes("NES_CPU_WR", 0x8000, 0x03)
		dict.nes("NES_CPU_WR", 0xA000, (cur_bank*4+3))	--1KB @ PPU $0C00

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
			--wr_chr_flash_byte(base_addr+byte_num, data, false)  --0.7KBps
			--EASIEST FIRMWARE SPEEDUP: 5x faster, create mapper write byte function:
			dict.nes("MMC3_CHR_FLASH_WR", base_addr+byte_num, data) --3.8KBps (5.5x faster than above)
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
		flash.write_file( file, 4, "MMC3", "CHRROM", false )

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
	-- FME7 has RAM capability present in some carts.
	local dumpram = process_opts["dumpram"]
	local ramdumpfile = process_opts["dumpram_filename"]
	local writeram = process_opts["writeram"]
	local ramwritefile = process_opts["writeram_filename"]

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
	end

--dump the ram to file 
	if dumpram then

		print("\nDumping WRAM...")

		init_mapper()
		
		--enable RAM at $6000
		dict.nes("NES_CPU_WR", 0x8000, 0x08)
		dict.nes("NES_CPU_WR", 0xA000, 0xC0)	--RAM enable, RAM mapped to $6000

		file = assert(io.open(ramdumpfile, "wb"))

		--dump cart into file
		dump_wram(file, wram_size, false)

		--for save data safety start by disable WRAM, and map PRG-ROM to $6000
		dict.nes("NES_CPU_WR", 0x8000, 0x08)
		dict.nes("NES_CPU_WR", 0xA000, 0x00)	--RAM disabled, ROM first bank mapped to $6000

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

		print("erasing PRG-ROM");
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


		--TODO erase CHR-ROM only if present
		init_mapper()

		print("erasing CHR-ROM");
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_PPU_WR", 0x1AAA, 0x55)
		dict.nes("NES_PPU_WR", 0x1555, 0x80)
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_PPU_WR", 0x1AAA, 0x55)
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
		
		--enable RAM at $6000
		dict.nes("NES_CPU_WR", 0x8000, 0x08)
		dict.nes("NES_CPU_WR", 0xA000, 0xC0)	--RAM enable, RAM mapped to $6000

		file = assert(io.open(ramwritefile, "rb"))

		flash.write_file( file, wram_size, "NOVAR", "PRGRAM", false )

		--for save data safety start by disable WRAM, and map PRG-ROM to $6000
		dict.nes("NES_CPU_WR", 0x8000, 0x08)
		dict.nes("NES_CPU_WR", 0xA000, 0x00)	--RAM disabled, ROM first bank mapped to $6000

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

		flash_prgrom(file, prg_size, true)
		flash_chrrom(file, chr_size, true)

		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then
		--for now let's just dump the file and verify manually
		print("\nPost dumping PRG & CHR ROMs...")

		init_mapper()

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		dump_prgrom(file, prg_size, false)
		dump_chrrom(file, chr_size, false)

		--close file
		assert(file:close())

		print("DONE post dumping PRG & CHR ROMs")
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
fme7.process = process

-- return the module's table
return fme7
