
-- create the module's table
local mmc1 = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local buffers = require "scripts.app.buffers"

-- file constants
local mapname = "MMC1"

-- local functions

local function create_header( file, prgKB, chrKB )

	--write_header( file, prgKB, chrKB, mapper, mirroring )
	nes.write_header( file, prgKB, chrKB, op_buffer[mapname], 0)
end


local function init_mapper( debug )

	--MMC1 ignores all but the first write
	dict.nes("NES_CPU_RD", 0x8000)
	--reset MMC1 shift register with D7 set
	dict.nes("NES_CPU_WR", 0x8000, 0x80)
	--this reset also effectively sets the control reg to 0x0C:
	--	prg mode 3: last 16KB fixed
	--	chr mode 0: single 8KB bank
	--	mirroring 0: 1 screen NT0

--	mmc1_write(0x8000, 0x10);       //32KB mode, prg bank @ $8000-FFFF, 4KB CHR mode
	dict.nes("NES_MMC1_WR", 0x8000, 0x10)
--	//note the mapper will constantly reset to this when writing to PRG-ROM
--	//PRG-ROM A18-A14

	--select first PRG-ROM bank, disable save RAM
	dict.nes("NES_MMC1_WR", 0xE000, 0x10)	--LSBit ignored in 32KB mode
						--bit4 RAM enable 0-enabled 1-disabled

--	//CHR-ROM A16-12 (A14-12 are required to be valid)
--	bit4 (CHR A16) is /CE pin for WRAM on SNROM
	dict.nes("NES_MMC1_WR", 0xA000, 0x12) --4KB bank @ PT0  $2AAA cmd and writes
	dict.nes("NES_MMC1_WR", 0xC000, 0x15) --4KB bank @ PT1  $5555 cmd fixed

end


--test the mapper's mirroring modes to verify working properly
--can be used to help identify board: returns true if pass, false if failed
local function mirror_test( debug )

	--put MMC1 in known state (mirror bits cleared)
	init_mapper() 

	--MM = 0: 1 screen A
	dict.nes("NES_MMC1_WR", 0x8000, 0x00)
	if (nes.detect_mapper_mirroring() ~= "1SCNA") then
		print("MMC1 mirror test fail (1 screen A)")
		return false
	end

	--MM = 1: 1 screen B
	dict.nes("NES_MMC1_WR", 0x8000, 0x01)
	if (nes.detect_mapper_mirroring() ~= "1SCNB") then
		print("MMC1 mirror test fail (1 screen B)")
		return false
	end

	--MM = 2: Vertical
	dict.nes("NES_MMC1_WR", 0x8000, 0x02)
	if (nes.detect_mapper_mirroring() ~= "VERT") then
		print("MMC1 mirror test fail (Vertical)")
		return false
	end

	--MM = 3: Horizontal
	dict.nes("NES_MMC1_WR", 0x8000, 0x03)
	if (nes.detect_mapper_mirroring() ~= "HORZ") then
		print("MMC1 mirror test fail (Horizontal)")
		return false
	end

	--passed all tests
	if(debug) then print("MMC1 mirror test passed") end
	return true
end


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

	--PRG-ROM dump 32KB at a time in 32KB bank mode
	local KB_per_read = 32
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x08	-- $8000

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		--select desired bank(s) to dump
		dict.nes("NES_MMC1_WR", 0xE000, read_count<<1)	--LSBit ignored in 32KB mode

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

	local KB_per_read = 8	--dump both PT
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00	-- $0000

	while ( read_count < num_reads ) do

		if debug then print( "dump CHR part ", read_count, " of ", num_reads) end

		dict.nes("NES_MMC1_WR", 0xA000, read_count*2) --4KB bank at $0000
		dict.nes("NES_MMC1_WR", 0xC000, read_count*2+1) --4KB bank at $1000

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
	--TODO update to NES_CPU_PAGE instead of NES_CPU_4KB

	while ( read_count < num_reads ) do

		if debug then print( "dump WRAM part ", read_count, " of ", num_reads) end

		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_4KB", false )

		read_count = read_count + 1
	end

end


--write a single byte to PRG-ROM flash
--PRE: assumes mapper is initialized and bank is selected as prescribed in mapper_init
--REQ: addr must be in the first bank $8000-FFFF
local function wr_prg_flash_byte(addr, value, bank, debug)

	if (addr < 0x8000 or addr > 0xFFFF) then
		print("\n  ERROR! flash write to PRG-ROM", string.format("$%X", addr), "must be $8000-FFFF \n\n")
		return
	end

--mmc1_wr(0x8000, 0x10, 0);               //32KB mode
--//IDK why, but somehow only the first byte gets programmed when ROM A14=1
--//so somehow it's getting out of 32KB mode for follow on bytes..
--//even though we reset to 32KB mode after the corrupting final write
--
--wr_func( unlock1, 0xAA );
--wr_func( unlock2, 0x55 );
--wr_func( unlock1, 0xA0 );
--wr_func( ((addrH<<8)| n), buff->data[n] );
--//writes to flash are to $8000-FFFF so any register could have been corrupted and shift register may be off
--//In reality MMC1 should have blocked all subsequent writes, so maybe only the CHR reg2 got corrupted..?                mmc1_wr(0x8000, 0x10, 1);               //32KB mode
--mmc1_wr(0xE000, bank, 0);       //reset shift register, and bank register

	--MMC1 ignores all but the first write
	--dict.nes("NES_CPU_RD", 0x8000)
--	dict.nes("NES_CPU_WR", 0x8000, 0x80) --reset MMC1 shift register with D7 set

	--dict.nes("NES_MMC1_WR", 0x8000, 0x10) --32KB mode, prg bank @ $8000-FFFF, 4KB CHR mode
	--doing this after the write doesn't work for some reason....
	--I think the reason this works is because the last instruction is a write (and it's valid)
	--so the next 4 writes are blocked by the MMC1 including the reset
	dict.nes("NES_MMC1_WR", 0xC000, 0x05)	--this seems to work as well which makes sense based on above..
	--so now all follow on writes will be blocked until there is a read

	--send unlock command and write byte
	dict.nes("NES_CPU_WR", 0xD555, 0xAA)	--this will reset the MMC1..?, 
						--but not if it was blocked by a previous write
	dict.nes("NES_CPU_WR", 0xAAAA, 0x55)	--blocked
	dict.nes("NES_CPU_WR", 0xD555, 0xA0)	--blocked
	dict.nes("NES_CPU_WR", addr, value)	--blocked

--	dict.nes("NES_CPU_RD", 0x8000)	--must read before resetting
--	dict.nes("NES_CPU_WR", 0x8000, 0x80) --reset MMC1 shift register with D7 set
--	dict.nes("NES_MMC1_WR", 0x8000, 0x10) --32KB mode, prg bank @ $8000-FFFF, 4KB CHR mode
--	dict.nes("NES_MMC1_WR", 0xE000, bank<<1) --32KB mode, prg bank @ $8000-FFFF, 4KB CHR mode

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
--REQ: addr must be in the first bank $0000-0FFF
local function wr_chr_flash_byte(addr, value, bank, debug)

	if (addr < 0x0000 or addr > 0x0FFF) then
		print("\n  ERROR! flash write to CHR-ROM", string.format("$%X", addr), "must be $0000-0FFF \n\n")
		return
	end

	--set banks for unlock commands
	dict.nes("NES_MMC1_WR", 0xA000, 0x02) --4KB bank @ PT0  $2AAA cmd and writes (always write data to PT0)
	--dict.nes("NES_MMC1_WR", 0xC000, 0x05) --4KB bank @ PT1  $5555 cmd fixed (never changed)

	--send unlock command and write byte
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
	dict.nes("NES_PPU_WR", 0x1555, 0xA0)

	--select desired bank for write
	dict.nes("NES_MMC1_WR", 0xA000, bank) --4KB bank @ PT0  $2AAA cmd and writes (always write data to PT0)
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
	--initial testing of MMC3 with no specific MMC3 flash firmware functions 6min per 256KByte = 0.7KBps


	local base_addr = 0x8000 --writes occur $8000-9FFF
	local bank_size = 32*1024 --MMC1 32KByte bank mode
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata


	while cur_bank < total_banks do

		if (cur_bank % 2 == 0) then
			print("writting PRG bank: ", cur_bank, " of ", total_banks-1)
		end

		--write the current bank to the mapper register
		dict.nes("NES_MMC1_WR", 0xE000, cur_bank<<1)	--LSBit ignored in 32KB mode

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
			--dict.nes("MMC1_PRG_FLASH_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)
			--NEXT STEP: firmware write page/bank function can use function pointer for the function above
			--	this may cause issues with more complex algos
			--	sometimes cur bank is needed 
			--	for this to work, need to have function post conditions meet the preconditions
			--	that way host intervention is only needed for bank controls
			--	Is there a way to allow for double buffering though..?
			--	YES!  just think of the bank as a complete memory
			--	this greatly simplifies things and is exactly where we want to go
			--	This is completed below outside the byte while loop @ 39KBps

			--local verify = true
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
		flash.write_file( file, bank_size/1024, mapname, "PRGROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")

end


--slow host flash one byte at a time...
--this is controlled from the host side byte by byte making it slow
--but doesn't require specific firmware mapper flashing functions
local function flash_chrrom(file, rom_size_KB, debug)

	init_mapper()

	print("\nProgramming CHR-ROM flash")

	--test some bytes
	--wr_chr_flash_byte(0x0000, 0xA5, 0, true)
	--wr_chr_flash_byte(0x0FFF, 0x5A, 0, true)
	

	local base_addr = 0x0000
	local bank_size = 4*1024 --MMC1 always write to PT0
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata


	while cur_bank < total_banks do

		if (cur_bank %8 == 0) then
			print("writting CHR bank: ", cur_bank, " of ", total_banks-1)
		end

		--select bank to flash
		dict.nes("SET_CUR_BANK", cur_bank) 
		if debug then print("get bank:", dict.nes("GET_CUR_BANK")) end
		--this only updates the firmware nes.c global
		--which it will use when calling mmc1_chrrom_flash_wr

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
			--wr_chr_flash_byte(base_addr+byte_num, data, cur_bank, false)  --0.7KBps
			--EASIEST FIRMWARE SPEEDUP: 5x faster, create mapper write byte function:
			dict.nes("MMC1_CHR_FLASH_WR", base_addr+byte_num, data) --3.8KBps (5.5x faster than above)
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
		flash.write_file( file, bank_size/1024, mapname, "CHRROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming CHR-ROM flash")
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
	-- MMC1 has RAM capability present in some carts.
	local dumpram = process_opts["dumpram"]
	local ramdumpfile = process_opts["dumpram_filename"]
	local writeram = process_opts["writeram"]
	local ramwritefile = process_opts["writeram_filename"]

	local rv = nil
	local file 
	local prg_size = console_opts["prg_rom_size_kb"]
	local chr_size = console_opts["chr_rom_size_kb"]
	local wram_size = console_opts["wram_size_kb"]

	--local filetype = "nes"	--skip over the first 16Bytes of file
	local filetype = "bin"
	
--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

--test cart by reading manf/prod ID
	if test then
		print("Testing ", mapname)

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
		
		--enable save ram
		dict.nes("NES_MMC1_WR", 0xE000, 0x00)	--bit4 RAM enable 0-enabled 1-disabled
	
		--bit4 (CHR A16) is /CE pin for WRAM on SNROM
		dict.nes("NES_MMC1_WR", 0xA000, 0x02) --4KB bank @ PT0  $2AAA cmd and writes
		dict.nes("NES_MMC1_WR", 0xC000, 0x05) --4KB bank @ PT1  $5555 cmd fixed

		file = assert(io.open(ramdumpfile, "wb"))

		--dump cart into file
		dump_wram(file, wram_size, false)

		--for save data safety disable WRAM, and deny writes
		dict.nes("NES_MMC1_WR", 0xE000, 0x10)	--bit4 RAM enable 0-enabled 1-disabled
	
		--bit4 (CHR A16) is /CE pin for WRAM on SNROM
		dict.nes("NES_MMC1_WR", 0xA000, 0x12) --4KB bank @ PT0  $2AAA cmd and writes
		dict.nes("NES_MMC1_WR", 0xC000, 0x15) --4KB bank @ PT1  $5555 cmd fixed

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
		if (chr_size ~= 0) then
			init_mapper()

			print("erasing CHR-ROM");
			dict.nes("NES_PPU_WR", 0x1555, 0xAA)
			dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
			dict.nes("NES_PPU_WR", 0x1555, 0x80)
			dict.nes("NES_PPU_WR", 0x1555, 0xAA)
			dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
			dict.nes("NES_PPU_WR", 0x1555, 0x10)
			rv = dict.nes("NES_PPU_RD", 0x8000)

			local i = 0

			--TODO create some function to pass the read value 
			--that's smart enough to figure out if the board is actually erasing or not
			while ( rv ~= 0xFF ) do
				rv = dict.nes("NES_PPU_RD", 0x8000)
				i = i + 1
			end
			print(i, "naks, done erasing chr.");
		end


	end

--write to wram on the cart
	if writeram then

		print("\nWritting to WRAM...")

		init_mapper()
		
		--enable save ram
		dict.nes("NES_MMC1_WR", 0xE000, 0x00)	--bit4 RAM enable 0-enabled 1-disabled
	
		--bit4 (CHR A16) is /CE pin for WRAM on SNROM
		dict.nes("NES_MMC1_WR", 0xA000, 0x02) --4KB bank @ PT0  $2AAA cmd and writes
		dict.nes("NES_MMC1_WR", 0xC000, 0x05) --4KB bank @ PT1  $5555 cmd fixed

		file = assert(io.open(ramwritefile, "rb"))

		flash.write_file( file, wram_size, "NOVAR", "PRGRAM", false )

		--for save data safety disable WRAM, and deny writes
		dict.nes("NES_MMC1_WR", 0xE000, 0x10)	--bit4 RAM enable 0-enabled 1-disabled
	
		--bit4 (CHR A16) is /CE pin for WRAM on SNROM
		dict.nes("NES_MMC1_WR", 0xA000, 0x12) --4KB bank @ PT0  $2AAA cmd and writes
		dict.nes("NES_MMC1_WR", 0xC000, 0x15) --4KB bank @ PT1  $5555 cmd fixed

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

		--flash cart
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
mmc1.process = process

-- return the module's table
return mmc1
