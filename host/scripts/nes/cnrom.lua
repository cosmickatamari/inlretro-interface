
-- create the module's table
local cnrom = {}

-- import required modules
local dict = require "scripts.app.dict"
local nes = require "scripts.app.nes"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local swim = require "scripts.app.swim"
local ciccom = require "scripts.app.ciccom"
local buffers = require "scripts.app.buffers"

-- file constants & variables
local mapname = "CNROM"
local banktable_base = 0x8000 --alwa
local rom_FF_addr = banktable_base+3 --generic 32KB CHR-ROM

-- local functions
local function find_ff_write_addr()
  -- scan for a PRG location that reads $FF to avoid bus conflicts
  for a = 0x8000, 0xFFFF do
    local v = dict.nes("NES_CPU_RD", a)
    if v == 0xFF then return a end
  end
  -- fallback (won't be ideal, but prevents nil)
  return 0x8000
end

local function create_header( file, prgKB, chrKB )
	local mirroring = nes.detect_mapper_mirroring()
	nes.write_header( file, prgKB, chrKB, op_buffer[mapname], mirroring)
end


local function find_banktable( debug )

	--TODO find/create the bank table
	
	--experimenting shows that writting to a byte where the bank bits are set
	--ie 0xFF (or 0x0F in case of 128KB CNROM), is good enough
	--the stm32 mcu can over power a 5v '1' with a 0, but can't overpower a 0 with a 3v '1'.
	
	--best solution is to dump the visible PRG-ROM and search for a bank table
	--then use that to swap banks
	
end

--read PRG-ROM flash ID
--this should be identical to NROM
local function prgrom_manf_id( debug )

	--init_mapper()

	if debug then print("reading PRG-ROM manf ID") end

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

	local rv
	--enter software mode
	--CNROM has A13 & A14 register controlled lower 2 bits of mapper
	--	    15 14 13 12
	-- 0x5 = 0b  0  1  0  1	-> $1555
	-- 0x2 = 0b  0  0  1  0	-> $0AAA
	--dict.nes("NES_CPU_WR", rom_FF_addr, 0x02)	--assumes mcu wins bus conflicts if rom is high
	dict.nes("NES_CPU_WR", banktable_base+2, 0x02)
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)

	--dict.nes("NES_CPU_WR", rom_FF_addr, 0x01)	--assumes mcu wins bus conflicts if rom is high
	dict.nes("NES_CPU_WR", banktable_base+1, 0x01)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)

	--dict.nes("NES_CPU_WR", rom_FF_addr, 0x02)	--assumes mcu wins bus conflicts if rom is high
	dict.nes("NES_CPU_WR", banktable_base+2, 0x02)
	dict.nes("NES_PPU_WR", 0x1555, 0x90)

	--read manf ID
	rv = dict.nes("NES_PPU_RD", 0x0000)
	if debug then print("attempted read CHR-ROM manf ID:", string.format("%X", rv)) end

	--read prod ID
	rv = dict.nes("NES_PPU_RD", 0x0001)
	if debug then print("attempted read CHR-ROM prod ID:", string.format("%X", rv)) end

	--exit software
	dict.nes("NES_PPU_WR", 0x0000, 0xF0)	--TODO bank table..?

end


--dump the PRG ROM
local function dump_prgrom( file, rom_size_KB, debug )

	--same as NROM
	local KB_per_read = 32
	if rom_size_KB < KB_per_read then KB_per_read = rom_size_KB end

	local num_reads = rom_size_KB / KB_per_read
	local read_count = 0
	local addr_base = 0x08	-- $8000

	while ( read_count < num_reads ) do

		if debug then print( "dump PRG part ", read_count, " of ", num_reads) end

		dump.dumptofile( file, KB_per_read, addr_base, "NESCPU_4KB", false )

		read_count = read_count + 1
	end

end

--dump the CHR ROM
local function dump_chrrom( file, rom_size_KB, debug )

  local KB_per_read = 8
  local num_reads   = rom_size_KB / KB_per_read
  local read_count  = 0
  local addr_base   = 0x00  -- $0000

  -- pick a safe address to write bank value (ROM byte must be $FF)
  local ff_addr = find_ff_write_addr()
  if debug then print(string.format("CNROM bank select write addr: $%04X", ff_addr)) end

  -- determine how many bank bits we should respect
  -- 8 KB per CHR bank
  local total_banks = num_reads
  -- CNROM variants commonly have 2 or 4 bank bits
  local bank_mask = (total_banks <= 4) and 0x03 or 0x0F

  while (read_count < num_reads) do
    if debug then print("dump CHR part ", read_count, " of ", num_reads) end

    local bank = bit32.band(read_count, bank_mask)

    -- single write: avoid changing addresses; avoid bus conflicts with non-$FF bytes
    dict.nes("NES_CPU_WR", ff_addr, bank)

    -- dump this bank (8 KB)
    dump.dumptofile( file, KB_per_read, addr_base, "NESPPU_1KB", false )

    read_count = read_count + 1
  end
end



--write a single byte to PRG-ROM flash
local function wr_prg_flash_byte(addr, value, debug)

	if (addr < 0x8000 or addr > 0xFFFF) then
		print("\n  ERROR! flash write to PRG-ROM", string.format("$%X", addr), "must be $8000-FFFF \n\n")
		return
	end

	--send unlock command and write byte
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

	--TODO handle timeout for problems

	--TODO return pass/fail/info
end


--write a single byte to CHR-ROM flash
--PRE: assumes mapper is initialized and bank is selected as prescribed in mapper_init
--REQ: addr must be in within Pattern Tables ($0000-1FFF)
local function wr_chr_flash_byte(bank, addr, value, debug)

	if (addr < 0x0000 or addr > 0x1FFF) then
		print("\n  ERROR! flash write to CHR-ROM", string.format("$%X", addr), "must be $0000-1FFF \n\n")
		return
	end

	--send unlock command
	--dict.nes("NES_CPU_WR", rom_FF_addr, 0x02)	--assumes mcu wins bus conflicts if rom is high
	dict.nes("NES_CPU_WR", banktable_base+2, 0x02)
	dict.nes("NES_PPU_WR", 0x1555, 0xAA)

	--dict.nes("NES_CPU_WR", rom_FF_addr, 0x01)	--assumes mcu wins bus conflicts if rom is high
	dict.nes("NES_CPU_WR", banktable_base+1, 0x01)
	dict.nes("NES_PPU_WR", 0x0AAA, 0x55)

	--dict.nes("NES_CPU_WR", rom_FF_addr, 0x02)	--assumes mcu wins bus conflicts if rom is high
	dict.nes("NES_CPU_WR", banktable_base+2, 0x02)
	dict.nes("NES_PPU_WR", 0x1555, 0xA0)

	--select desired bank
	--dict.nes("NES_CPU_WR", rom_FF_addr, bank)	--assumes mcu wins bus conflicts if rom is high
	dict.nes("NES_CPU_WR", banktable_base+bank, bank)
	--write the byte
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



local function flash_prgrom(file, rom_size_KB, debug)


	print("\nProgramming PRG-ROM flash")

	local base_addr = 0x8000 --writes occur $8000-9FFF
	local bank_size = 32*1024 --MMC3 8KByte per PRG bank
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata

	while cur_bank < total_banks do

		if (cur_bank %8 == 0) then
			print("writting PRG bank: ", cur_bank, " of ", total_banks-1)
		end

		--program the entire bank's worth of data
	--same as NROM
		flash.write_file( file, 32, "NROM", "PRGROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming PRG-ROM flash")

end


local function flash_chrrom(file, rom_size_KB, debug)

	--init_mapper()

	--test some bytes
	--wr_chr_flash_byte(0x00, 0x0000, 0x03, true)
	--wr_chr_flash_byte(0x00, 0x1FFF, 0x0C, true)
	--wr_chr_flash_byte(0x01, 0x0000, 0x13, true)
	--wr_chr_flash_byte(0x01, 0x1FFF, 0x1C, true)
	--wr_chr_flash_byte(0x02, 0x0000, 0x23, true)
	--wr_chr_flash_byte(0x02, 0x1FFF, 0x2C, true)
	--wr_chr_flash_byte(0x03, 0x0000, 0x33, true)
	--wr_chr_flash_byte(0x03, 0x1FFF, 0x3C, true)
	--wr_chr_flash_byte(0x04, 0x0000, 0x43, true)
	--wr_chr_flash_byte(0x04, 0x1FFF, 0x4C, true)
	--wr_chr_flash_byte(0x05, 0x0000, 0x53, true)
	--wr_chr_flash_byte(0x05, 0x1FFF, 0x5C, true)
	--wr_chr_flash_byte(0x06, 0x0000, 0x63, true)
	--wr_chr_flash_byte(0x06, 0x1FFF, 0x6C, true)
	--wr_chr_flash_byte(0x07, 0x0000, 0x73, true)
	--wr_chr_flash_byte(0x07, 0x1FFF, 0x7C, true)
	--wr_chr_flash_byte(0x08, 0x0000, 0x83, true)
	--wr_chr_flash_byte(0x08, 0x1FFF, 0x8C, true)
	--wr_chr_flash_byte(0x09, 0x0000, 0x93, true)
	--wr_chr_flash_byte(0x09, 0x1FFF, 0x9C, true)
	--wr_chr_flash_byte(0x0A, 0x0000, 0xA3, true)
	--wr_chr_flash_byte(0x0A, 0x1FFF, 0xAC, true)
	--wr_chr_flash_byte(0x0B, 0x0000, 0xB3, true)
	--wr_chr_flash_byte(0x0B, 0x1FFF, 0xBC, true)
	--wr_chr_flash_byte(0x0C, 0x0000, 0xC3, true)
	--wr_chr_flash_byte(0x0C, 0x1FFF, 0xCC, true)
	--wr_chr_flash_byte(0x0D, 0x0000, 0xD3, true)
	--wr_chr_flash_byte(0x0D, 0x1FFF, 0xDC, true)
	--wr_chr_flash_byte(0x0E, 0x0000, 0xE3, true)
	--wr_chr_flash_byte(0x0E, 0x1FFF, 0xEC, true)
	--wr_chr_flash_byte(0x0F, 0x0000, 0xF3, true)
	--wr_chr_flash_byte(0x0F, 0x1FFF, 0xFC, true)
	
	print("\nProgramming CHR-ROM flash")
      	--most of this is overkill for NROM, but it's how we want to handle things for bigger mappers

	local base_addr = 0x0000
	local bank_size = 8*1024 
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata

	--set the bank table address
	dict.nes("SET_BANK_TABLE", banktable_base) 
	if debug then print("get banktable:", string.format("%X", dict.nes("GET_BANK_TABLE"))) end

	while cur_bank < total_banks do

		if (cur_bank %8 == 0) then
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
			dict.nes("CNROM_CHR_FLASH_WR", base_addr+byte_num, data) 
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

	local filetype = "nes"
	--local filetype = "bin"
	--
--initialize device i/o for NES
	dict.io("IO_RESET")
	dict.io("NES_INIT")

--test the cart
	if test then
		print("Testing", mapname)
		nes.detect_mapper_mirroring(true)
	
		print("EXP0 pull-up test:", dict.io("EXP0_PULLUP_TEST"))	
		prgrom_manf_id( true )

		chrrom_manf_id( true )

	end

--dump the cart to dumpfile
	if read then
		print("\nDumping PRG & CHR ROMs...")

		file = assert(io.open(dumpfile, "wb"))

		--create header: pass open & empty file & rom sizes
		create_header(file, prg_size, chr_size)

		--dump cart into file
		dump_prgrom(file, prg_size, true)
		dump_chrrom(file, chr_size, true)

		--close file
		assert(file:close())
		print("DONE Dumping PRG & CHR ROMs")
	end


--erase the cart
	if erase then

		print("\nErasing ", mapname);

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
		--there probably isn't a bank table if PRG-ROM just erased...
		--but if PRG-ROM is erased (all 0xFF) mcu should be able to write to any address
		--dict.nes("NES_CPU_WR", rom_FF_addr, 0x02)	--assumes mcu can write a 0 to a 1
		dict.nes("NES_CPU_WR", banktable_base+2, 0x02)
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		--dict.nes("NES_CPU_WR", rom_FF_addr, 0x01)	--assumes mcu can write a 0 to a 1
		dict.nes("NES_CPU_WR", banktable_base+1, 0x01)
		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
		--dict.nes("NES_CPU_WR", rom_FF_addr, 0x02)	--assumes mcu can write a 0 to a 1
		dict.nes("NES_CPU_WR", banktable_base+2, 0x02)
		dict.nes("NES_PPU_WR", 0x1555, 0x80)
		--dict.nes("NES_CPU_WR", rom_FF_addr, 0x02)	--assumes mcu can write a 0 to a 1
		dict.nes("NES_CPU_WR", banktable_base+2, 0x02)
		dict.nes("NES_PPU_WR", 0x1555, 0xAA)
		--dict.nes("NES_CPU_WR", rom_FF_addr, 0x01)	--assumes mcu can write a 0 to a 1
		dict.nes("NES_CPU_WR", banktable_base+1, 0x01)
		dict.nes("NES_PPU_WR", 0x0AAA, 0x55)
		--dict.nes("NES_CPU_WR", rom_FF_addr, 0x02)	--assumes mcu can write a 0 to a 1
		dict.nes("NES_CPU_WR", banktable_base+2, 0x02)
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
		print("\nPost Dumping PRG & CHR ROMs...")

		file = assert(io.open(verifyfile, "wb"))

		--dump cart into file
		dump_prgrom(file, prg_size, false)
		dump_chrrom(file, chr_size, false)

		--close file
		assert(file:close())
		print("DONE Post Dumping PRG & CHR ROMs")
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
cnrom.process = process

-- return the module's table
return cnrom
