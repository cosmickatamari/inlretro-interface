
-- create the module's table
local cdream = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local help = require "scripts.app.help"
local time = require "scripts.app.time"
local files = require "scripts.app.files"
local buffers = require "scripts.app.buffers"

-- file constants & variables
local mapname = "CDREAM"
--local banktable_base = 0xCC43 --MTales, bank0 only though..
--local banktable_base = 0xCC29 --MTales, bank0 only though..
----local rom_FF_addr = 0xCD42 --Alfonzo present in each bank  write any value here will work if zeros always win
--local rom_FF_addr = 0xCD28 --Alfonzo present in each bank  write any value here will work if zeros always win
--local rom_00_addr = 0x800C --Alfonzo present in each bank  write 0 here to ensure bank 0
--local num_prg_banks = 16       --bank table size and organization depends on number of PRG banks

local banktable_base = 0xFF9E --Alfonzo all banks
local num_prg_banks = 4       --bank table size and organization depends on number of PRG banks
local rom_FF_addr = 0x8008 --Alfonzo present in each bank  write any value here will work if zeros always win
local rom_00_addr = 0xFF9E --Alfonzo present in each bank  write 0 here to ensure bank 0
--perhaps can use this to always get back to first bank which has a complete bank table
--MTales does have a zero in each and every bank at $800C which could be used to get back to bank0
--but for now let's rely on 0 always overriding 1 to allow us to always be able to get to bank0

-- local functions

local function create_header( file, prgKB, chrKB )

	local mirroring = nes.detect_mapper_mirroring()

	--write_header( file, prgKB, chrKB, mapper, mirroring )
	nes.write_header( file, prgKB, chrKB, op_buffer[mapname], mirroring)
end

--read PRG-ROM flash ID
local function prgrom_manf_id( debug )

	--init_mapper()

	if debug then print("reading PRG-ROM manf ID") end

	--enter software mode
	--ROMSEL controls PRG-ROM /OE which needs to be low for flash writes
	--So unlock commands need to be addressed below $8000
	--DISCRETE_EXP0_PRGROM_WR doesn't toggle /ROMSEL by definition though, so A15 is unused
	--	    15 14 13 12
	-- 0x5 = 0b  0  1  0  1	-> $5555
	-- 0x2 = 0b  0  0  1  0	-> $2AAA
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x90)

	--read manf ID
	local rv = dict.nes("NES_CPU_RD", 0x8000)
	if debug then print("attempted read PRG-ROM manf ID:", string.format("%X", rv)) end

	--read prod ID
	rv = dict.nes("NES_CPU_RD", 0x8001)
	if debug then print("attempted read PRG-ROM prod ID:", string.format("%X", rv)) end

	--exit software
	dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x8000, 0xF0)

end

--read CHR-ROM flash ID
local function chrrom_manf_id( debug )

	--init_mapper()

	if debug then print("reading CHR-ROM manf ID") end

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

end


local function wr_prg_flash_byte(addr, value, debug)

	--same as NROM
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


--write a single byte to CHR-ROM flash
--PRE: assumes mapper is initialized and bank is selected
--REQ: addr must be in within Pattern Tables ($0000-1FFF)
local function wr_chr_flash_byte(bank, addr, value, debug)

	if (addr < 0x0000 or addr > 0x1FFF) then
		print("\n  ERROR! flash write to CHR-ROM", string.format("$%X", addr), "must be $0000-1FFF \n\n")
		return
	end

	--Color Dreams CHR-ROM register is mapper bits 4-7 (upper nibble)
	--need to ensure first PRG-ROM bank is selected because that's only bank with the table
	dict.nes("NES_CPU_WR", rom_00_addr, 0x00)	--assumes mcu wins bus conflicts if rom is high
	--remaining bank switches should maintain PRG-ROM bank 0 selected

	--send unlock command
	--dict.nes("NES_CPU_WR", rom_00_addr, 0x00)	--assumes mcu wins bus conflicts if rom is high
	--dict.nes("NES_CPU_WR", rom_FF_addr, 0x20)	--assumes mcu wins bus conflicts if rom is high
	--dict.nes("NES_CPU_WR", banktable_base+0x20, 0x20) --alfonzo doesn't have this large of bank table
	dict.nes("NES_CPU_WR", banktable_base+ num_prg_banks*2 , 0x20)
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)

	--dict.nes("NES_CPU_WR", rom_00_addr, 0x00)	--assumes mcu wins bus conflicts if rom is high
	--dict.nes("NES_CPU_WR", rom_FF_addr, 0x10)	--assumes mcu wins bus conflicts if rom is high
	--dict.nes("NES_CPU_WR", banktable_base+0x10, 0x10)
	dict.nes("NES_CPU_WR", banktable_base+ num_prg_banks*1 , 0x10)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)

	--dict.nes("NES_CPU_WR", rom_00_addr, 0x00)	--assumes mcu wins bus conflicts if rom is high
	--dict.nes("NES_CPU_WR", rom_FF_addr, 0x20)	--assumes mcu wins bus conflicts if rom is high
	--dict.nes("NES_CPU_WR", banktable_base+0x20, 0x20)
	dict.nes("NES_CPU_WR", banktable_base+ num_prg_banks*2 , 0x20)
	dict.nes("NES_PPU_WR", 0x1555, 0xA0)

	--select desired bank
	--dict.nes("NES_CPU_WR", rom_00_addr, 0x00)	--assumes mcu wins bus conflicts if rom is high
	--dict.nes("NES_CPU_WR", rom_FF_addr, bank<<4)	--assumes mcu wins bus conflicts if rom is high
	dict.nes("NES_CPU_WR", banktable_base+(bank*num_prg_banks), (bank<<4))
	--dict.nes("NES_CPU_WR", banktable_base+bank, bank)
	--write the byte
	dict.nes("NES_PPU_WR", addr, value)

	local rv = dict.nes("NES_PPU_RD", addr)

	local i = 0

	while ( rv ~= dict.nes("NES_PPU_RD", addr) ) do
		i = i + 1

		print(help.hex(rv))

		if i > 100 then
			print("naks > 100, write failed, addr:", help.hex(addr), "data:", help.hex(value),"readback:", help.hex(rv) )
			return
		end
	end
	if debug then print(i, "naks, done writing byte.") end

	--TODO handle timeout for problems

	--TODO return pass/fail/info
end


--base is the actual NES CPU address, not the rom offset (ie $FFF0, not $7FF0)
local function wr_bank_table(base, entries)

	--CDREAMS needs to have a bank table present in each and every bank
	--it should also be at the same location in every bank
	--Perhaps it's possible to squeak by with only having it in the first bank as mojontales does..
	
	--doesn't actually matter what bank this gets written to, lets ensure we can get to bank zero
--	wr_prg_flash_byte(0x800C, 0x00)

	--select first bank relying on 0 to override 1 for bus conflict
	dict.nes("NES_CPU_WR", banktable_base, 0x00)

	--write bank table to selected bank
	local i = 0
	while( i < entries) do
		wr_prg_flash_byte(base+i, i)
		i = i+1;
	end


--	--need a zero value in each bank to get back to first bank
--	wr_prg_flash_byte(0x800C, 0x00)	--first bank
--
--	--now place one in all the other banks
--	--first swap to next bank
--	i = 1
--	while( i < 16) do	--16 banks total for 512KByte
--		dict.nes("NES_CPU_WR", 0x0000, 0x00)	--select first bank
--		dict.nes("NES_CPU_WR", base+i, i)	--jump to next bank
--		wr_prg_flash_byte(0x800C, 0x00)		--write zero byte
--		i = i + 1
--	end
	

end


--dump the PRG ROM
local function dump_prgrom( file, rom_size_KB, debug )

	local KB_per_read = 32
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x08	-- $8000

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		--first need to get back to bank 0 where the bank table is
		dict.nes("NES_CPU_WR", rom_00_addr, 0x00)

		--select desired bank(s) to dump
		dict.nes("NES_CPU_WR", banktable_base+read_count, read_count)	--32KB @ CPU $8000

		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_4KB", false )

		read_count = read_count + 1
	end

end


--dump the CHR ROM
local function dump_chrrom( file, rom_size_KB, debug )

	--CHR-ROM dump 8KB at a time
	local KB_per_read = 8	
	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x00	-- $0000

	while ( read_count < num_reads ) do

		if debug then print( "dump CHR part ", read_count, " of ", num_reads) end

		--first need to get back to bank 0 where the bank table is
		dict.nes("NES_CPU_WR", rom_00_addr, 0x00)

		--select the proper CHR-ROM bank
		--dump/read size is equal to bank size, so read_count is equal to bank number
		dict.nes("NES_CPU_WR", rom_FF_addr, read_count<<4)
		--dict.nes("NES_CPU_WR", banktable_base+(read_count<<4), (read_count<<4))

		--dump the bank
		dump.dumptofile( file, KB_per_read, addr_base, "NESPPU_1KB", false )

		read_count = read_count + 1
	end

end


--host flash one byte/bank at a time...
--this is controlled from the host side one bank at a time
--but requires mapper specific firmware flashing functions
local function flash_prgrom(file, rom_size_KB, debug)

	--init_mapper()
	
	--bank table should already be written
	
	--test some bytes
	--wr_prg_flash_byte(0x0000, 0xA5, true)
	--wr_prg_flash_byte(0xFFFF, 0x5A, true)

	print("\nProgramming PRG-ROM flash")

	local base_addr = 0x8000 --writes occur $8000-9FFF
	local bank_size = 32*1024 --just like BNROM 32KByte per PRG bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata

	while cur_bank < total_banks do

		if (cur_bank %2 == 0) then
			print("writting PRG bank: ", cur_bank, " of ", total_banks-1)
		end

		--first need to get back to bank 0 where the bank table is
		dict.nes("NES_CPU_WR", rom_00_addr, 0x00)
		--write the current bank to the mapper register this should be written to bank table
		dict.nes("NES_CPU_WR", banktable_base+cur_bank, cur_bank)

		--program the entire bank's worth of data

		--[[  This version of the code programs a single byte at a time but doesn't require 
		--	MMC3 specific functions in the firmware
		print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware MMC3 specific functions 100% host flash algo:
			--wr_prg_flash_byte(base_addr+byte_num, data, false)   --0.7KBps
			--EASIEST FIRMWARE SPEEDUP: 5x faster, create MMC3 write byte function:
			--can use same write function as NROM
			dict.nes("NROM_PRG_FLASH_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)

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
		--Same as NROM
		flash.write_file( file, bank_size/1024, "NROM", "PRGROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")

end


local function flash_chrrom(file, rom_size_KB, debug)

	--init_mapper()

	--test some bytes
	--print("test writes")
	--wr_chr_flash_byte(0x00, 0x0000, 0x03, true) wr_chr_flash_byte(0x00, 0x1FFF, 0x0C, true)
	--wr_chr_flash_byte(0x01, 0x0000, 0x13, true) wr_chr_flash_byte(0x01, 0x1FFF, 0x1C, true)
	--wr_chr_flash_byte(0x02, 0x0000, 0x23, true) wr_chr_flash_byte(0x02, 0x1FFF, 0x2C, true)
	--wr_chr_flash_byte(0x03, 0x0000, 0x33, true) wr_chr_flash_byte(0x03, 0x1FFF, 0x3C, true)
	--wr_chr_flash_byte(0x04, 0x0000, 0x43, true) wr_chr_flash_byte(0x04, 0x1FFF, 0x4C, true)
	--wr_chr_flash_byte(0x05, 0x0000, 0x53, true) wr_chr_flash_byte(0x05, 0x1FFF, 0x5C, true)
	--wr_chr_flash_byte(0x06, 0x0000, 0x63, true) wr_chr_flash_byte(0x06, 0x1FFF, 0x6C, true)
	--wr_chr_flash_byte(0x07, 0x0000, 0x73, true) wr_chr_flash_byte(0x07, 0x1FFF, 0x7C, true)
	--wr_chr_flash_byte(0x08, 0x0000, 0x83, true) wr_chr_flash_byte(0x08, 0x1FFF, 0x8C, true)
	--wr_chr_flash_byte(0x09, 0x0000, 0x93, true) wr_chr_flash_byte(0x09, 0x1FFF, 0x9C, true)
	--wr_chr_flash_byte(0x0A, 0x0000, 0xA3, true) wr_chr_flash_byte(0x0A, 0x1FFF, 0xAC, true)
	--wr_chr_flash_byte(0x0B, 0x0000, 0xB3, true) wr_chr_flash_byte(0x0B, 0x1FFF, 0xBC, true)
	--wr_chr_flash_byte(0x0C, 0x0000, 0xC3, true) wr_chr_flash_byte(0x0C, 0x1FFF, 0xCC, true)
	--wr_chr_flash_byte(0x0D, 0x0000, 0xD3, true) wr_chr_flash_byte(0x0D, 0x1FFF, 0xDC, true)
	--wr_chr_flash_byte(0x0E, 0x0000, 0xE3, true) wr_chr_flash_byte(0x0E, 0x1FFF, 0xEC, true)
	--wr_chr_flash_byte(0x0F, 0x0000, 0xF3, true) wr_chr_flash_byte(0x0F, 0x1FFF, 0xFC, true)
	
	print("\nProgramming CHR-ROM flash")
      	--most of this is overkill for NROM, but it's how we want to handle things for bigger mappers

	--if 1 then return end

	local base_addr = 0x0000
	local bank_size = 8*1024 
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata

	--start with the first bank selected so the bank table is visible
	--only really need banktable present in a single PRG bank
	--having it in the first bank is easiest to access with assumption that 0 beats 1 on bus conflicts
	dict.nes("NES_CPU_WR", rom_00_addr, 0x00)	--assumes mcu wins bus conflicts if rom is high

	--set the bank table address
	dict.nes("SET_BANK_TABLE", banktable_base) 
	if debug then print("get banktable:", string.format("%X", dict.nes("GET_BANK_TABLE"))) end

	--tell firmware number of PRG-ROM banks so it knows the structure of the banktable
	dict.nes("SET_NUM_PRG_BANKS", num_prg_banks)
	if debug then print("get num prg banks:", dict.nes("GET_NUM_PRG_BANKS")) end

	while cur_bank < total_banks do

		if (cur_bank %2 == 0) then
			print("writting CHR bank: ", cur_bank, " of ", total_banks-1)
		end

		--select bank to flash
		dict.nes("SET_CUR_BANK", cur_bank) 
		if debug then print("get bank:", dict.nes("GET_CUR_BANK")) end
		--this only updates the firmware nes.c global
		--which it will use when calling cnrom_chrrom_flash_wr


		--[[  This version of the code programs a single byte at a time but doesn't require 
		--	mapper specific functions in the firmware
		print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware MMC3 specific functions 100% host flash algo:
			--wr_chr_flash_byte(cur_bank, base_addr+byte_num, data, false)  --0.7KBps
			--EASIEST FIRMWARE SPEEDUP: 5x faster, create mapper write byte function:
			--dict.nes("CDREAM_CHR_FLASH_WR", base_addr+byte_num, data) 
			--FASTEST have the firmware handle flashing a bank's worth of data
			--control the init and banking from the host side
			
			--verify write after it's complete
			if (true) then
				readdata = dict.nes("NES_PPU_RD", base_addr+byte_num)
				if readdata ~= data then
					print("ERROR flashing byte number", byte_num, " in bank",cur_bank, " to flash ", data, readdata)
				end
			end

			byte_num = byte_num + 1
		end
		--]]

		--program the entire bank's worth of data
		flash.write_file( file, 8, mapname, "CHRROM", false )

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

		nes.detect_mapper_mirroring(true)
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	
		prgrom_manf_id(true)

		chrrom_manf_id(true)

		--verify mirroring if desired
		--if ( nes.detect_mapper_mirroring() == "VERT" ) then
		--	if debug then print("pass VERT mirror test") end
		--else
		--	print("\n\n\nFAIL MIRRORING JUMPER IS NOT VERTICAL!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n\n")
		--	--don't continue
		--	return false
		--end
		--if ( nes.detect_mapper_mirroring() == "HORZ" ) then
		--	if debug then print("pass VERT mirror test") end
		--else
		--	print("\n\n\nFAIL MIRRORING JUMPER IS NOT HORIZONTAL!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n\n")
		--	--don't continue
		--	return false
		--end
	end

--dump the cart to dumpfile
	if read then
		print("\nDumping PRG & CHR ROMs...")
		file = assert(io.open(dumpfile, "wb"))

		--create header: pass open & empty file & rom sizes
		create_header(file, prg_size, chr_size)

		--TODO find bank table to avoid bus conflicts!
		--dump cart into file
		dump_prgrom(file, prg_size, false)
		dump_chrrom(file, chr_size, false)

		--close file
		assert(file:close())
		print("DONE Dumping PRG & CHR ROMs")
	end


--erase the cart
	if erase then

		print("\nerasing CDREAM");

		print("erasing PRG-ROM");
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x80)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0xAA)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x2AAA, 0x55)
		dict.nes("DISCRETE_EXP0_PRGROM_WR", 0x5555, 0x10)
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
		dict.nes("NES_CPU_WR", 0x8000, 0x20) dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_CPU_WR", 0x8000, 0x10) dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
		dict.nes("NES_CPU_WR", 0x8000, 0x20) dict.nes("NES_PPU_WR", 0x1555, 0x80)
		dict.nes("NES_CPU_WR", 0x8000, 0x20) dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		dict.nes("NES_CPU_WR", 0x8000, 0x10) dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
		dict.nes("NES_CPU_WR", 0x8000, 0x20) dict.nes("NES_PPU_WR", 0x1555, 0x10)

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

		--find bank table in the rom
		--write bank table to all banks of cartridge
		--Mojontales bank table is at $CC43 so hard code that for now
		--wr_bank_table(banktable_base, 256)
		wr_bank_table(banktable_base, 4)

		--flash cart
		flash_prgrom(file, prg_size, false)
		flash_chrrom(file, chr_size, false)

		--close file
		assert(file:close())

	end

--verify flashfile is on the cart
	if verify then

		file = assert(io.open(verifyfile, "wb"))

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
cdream.process = process

-- return the module's table
return cdream
