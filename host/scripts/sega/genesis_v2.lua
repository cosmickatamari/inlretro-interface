
-- create the module's table
local genesis_v2= {}

-- import required modules
local dict = require "scripts.app.dict"
local dump = require "scripts.app.dump"
local flash = require "scripts.app.flash"
local help = require "scripts.app.help"

-- file constants

-- local functions

local function unsupported(operation)
	print("\nUNSUPPORTED OPERATION: \"" .. operation .. "\" not implemented yet for Sega Genesis.\n")
end

-- Compute Genesis checksum from a file, which can be compared with header value.
local function checksum_rom(filename)
	local file = assert(io.open(filename, "rb"))
	local sum = 0
	-- Skip header
	file:read(0x200)
	while true do
		-- Add up remaining 16-bit words
		local bytes = file:read(2)
		if not bytes then break end
		sum = sum + string.unpack(">i2", bytes)
	end
	-- Only use the lower bits.
	return sum & 0xFFFF
end

--/ROMSEL is always low for this dump
local function dump_rom( file, rom_size_KB, debug )

	local KB_per_bank = 128	  -- A1-16 = 64K address space, 2Bytes per address
	local addr_base = 0x0000  -- control signals are manually controlled


	local num_reads = rom_size_KB / KB_per_bank
	local read_count = 0

	while (read_count < num_reads) do

		if debug then print( "Dumping ROM part ", read_count + 1, " of ", num_reads) end

		-- A "large" Genesis ROM is 24 banks, many are 8 and 16 - status every 4 is reasonable.
		-- The largest published Genesis game is Super Street Fighter 2, which is 40 banks!
		-- TODO: Accessing banks in games that are >4MB require using a mapper.
		-- See: https://plutiedev.com/beyond-4mb

		if (read_count % 4 == 0) then
			print("dumping ROM bank: ", read_count, " of ", num_reads - 1)
		end

		-- Select desired bank.
		dict.sega("GEN_SET_BANK", read_count)

		dump.dumptofile(file, KB_per_bank/2, addr_base, "GENESIS_ROM_PAGE0", debug)
		dump.dumptofile(file, KB_per_bank/2, addr_base, "GENESIS_ROM_PAGE1", debug)

		read_count = read_count + 1
	end

end

-- Helper to extract fields in internal header.
local function extract_field_from_string(data, start_offset, length)
	-- 1 is added to Offset to handle lua strings being 1-based.
	return string.sub(data, start_offset + 1, start_offset + length)
end

-- Populates table with internal header contents from dumped data.
local function extract_header(header_data)
	-- https://plutiedev.com/rom-header
	-- https://en.wikibooks.org/wiki/Genesis_Programming#ROM_header
	
	-- TODO: Decode publisher from t-series in build field
	-- https://segaretro.org/Third-party_T-series_codes

	local addr_console_name 		= 0x100
	local addr_build_date 			= 0x110
	local addr_domestic_name 		= 0x120
	local addr_intl_name 			= 0x150
	local addr_type_serial_version 	= 0x180
	local addr_checksum 			= 0x18E
	local addr_device_support 		= 0x190
	local addr_rom_addr_range 		= 0x1A0
	local addr_ram_addr_range 		= 0x1A8
	local addr_sram_support 		= 0x1B0
	local addr_modem_support 		= 0x1BC
	local addr_region_support 		= 0x1F0

	local len_console_name = 16
	local len_build_date = 16
	local len_name = 48
	local len_type_serial_version = 14
	local len_checksum = 2
	local len_device_support = 16
	local len_addr_range = 8
	local len_sram_support = 12
	local len_modem_support = 12
	local len_region_support = 3

	local header = {
		console_name = extract_field_from_string(header_data, addr_console_name, len_console_name),
		-- TODO: Decode T-Value and build info.
		build_date = extract_field_from_string(header_data, addr_build_date, len_build_date),
		domestic_name = extract_field_from_string(header_data, addr_domestic_name, len_name),
		international_name = extract_field_from_string(header_data, addr_intl_name, len_name),
		-- TODO: Decode Type, serial and revision.
		type_serial_version = extract_field_from_string(header_data, addr_type_serial_version, len_type_serial_version),
		checksum = string.unpack(">i2", extract_field_from_string(header_data, addr_checksum, len_checksum)), 
		-- TODO: Decode device support.
		io_device_support = extract_field_from_string(header_data, addr_device_support, len_device_support),
		-- TODO: Decode SRAM support.
		sram_support = extract_field_from_string(header_data, addr_sram_support, len_sram_support),
		-- TODO: Decode modem support.
		modem_support = extract_field_from_string(header_data, addr_modem_support, len_modem_support),
		-- TODO: Decode region support.
		region_support = extract_field_from_string(header_data, addr_region_support, len_region_support),
	}
	-- ROM range can be used to autodetect the rom size.
	local rom_range = extract_field_from_string(header_data, addr_rom_addr_range, len_addr_range)
	local rom_start = string.unpack(">i4", string.sub(rom_range, 1, 4))
	local rom_end = string.unpack(">i4", string.sub(rom_range,5, 8))
	header["rom_size"] = (rom_end - rom_start + 1) / 1024

	-- These should be the same in every cart according to docs, but decode in case its not. (64 Kb)
	local ram_range = extract_field_from_string(header_data, addr_ram_addr_range, len_addr_range)
	local ram_start = string.unpack(">i4", string.sub(ram_range, 1, 4))
	local ram_end = string.unpack(">i4", string.sub(ram_range,5, 8))
	header["ram_size"] = (ram_end - ram_start + 1) / 1024
	
	return header
end

-- Make a human-friendly text representation of ROM Size.
local function str_rom_size(rom_size_kb)
	local mbit = rom_size_kb / 128
	if mbit < 1 then
		mbit = "<1"
	end
	return "" .. rom_size_kb .. " kB (".. mbit .." mbit)" 
end

-- Prints parsed header contents to stdout.
local function print_header(genesis_header)
	print("Console Name: \t" .. genesis_header["console_name"])
	print("Domestic Name: \t" .. genesis_header["domestic_name"])
	print("Release Date: \t" .. genesis_header["build_date"])
	print("Rom Size: \t" .. str_rom_size(genesis_header["rom_size"]))
	print("Serial/Version: " .. genesis_header["type_serial_version"])
	print("Checksum: \t" .. hexfmt(genesis_header["checksum"]))
end

-- Reads and parses internal ROM header from first page of data.
local function read_header()
	dict.sega("GEN_SET_BANK", 0)

	local page0_data = ""
	dump.dumptocallback(
		function (data)
			page0_data = page0_data .. data
		end,
		64, 0x0000, "GENESIS_ROM_PAGE0", false
	)
	local header_data = string.sub(page0_data, 1, 0x201)
	local genesis_header = extract_header(header_data)
	return genesis_header
end

-- Test that cartridge is readable by looking for valid entries in internal header.
local function test(genesis_header)

	---[[
	--test some functions
	--read "SEGA" from the in rom header
	dict.sega("GEN_SET_BANK", 0)
	local temp
	temp = dict.sega("GEN_ROM_RD", (0x0100>>1))
	print(help.hex(temp)) --"SE"
	print(string.char(temp>>8)) --"S"
	print(string.char(temp&0x00FF)) --"E"
	temp = dict.sega("GEN_ROM_RD", (0x0102>>1))
	print(help.hex(temp)) --"GA"
	print(string.char(temp>>8)) --"G"
	print(string.char(temp&0x00FF)) --"A"

	--flash manf ID
	print("flash write")
	dict.sega("GEN_SET_BANK", 0)
	dict.sega("GEN_SET_ADDR", 0x5555)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x00AA, 0)

	dict.sega("GEN_SET_ADDR", 0x2AAA)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x0055, 0)

	dict.sega("GEN_SET_ADDR", 0x5555)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x0090, 0)
	temp = dict.sega("GEN_ROM_RD", (0x0000>>1))
	print(help.hex(temp)) --"SE"
	temp = dict.sega("GEN_ROM_RD", (0x0002>>1))
	print(help.hex(temp)) --"SE"

	print("HI write")
	dict.sega("GEN_WR_HI", 0x5555, 0xAA) --A16-1
	dict.sega("GEN_WR_HI", 0x2AAA, 0x55) --A16-1
	dict.sega("GEN_WR_HI", 0x5555, 0x90) --A16-1
	temp = dict.sega("GEN_ROM_RD", (0x0000>>1))
	print(help.hex(temp)) --"SE"
	temp = dict.sega("GEN_ROM_RD", (0x0002>>1))
	print(help.hex(temp)) --"SE"

	--exit software mode
	print("exit software mode")
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x00F0, 0)
	temp = dict.sega("GEN_ROM_RD", (0x0000>>1))
	print(help.hex(temp)) --"SE"


	--write a byte
	--[[
	print("write a byte $0000, AAAA")
	dict.sega("GEN_SET_BANK", 0)
	dict.sega("GEN_SET_ADDR", 0x5555)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x00AA, 0)

	dict.sega("GEN_SET_ADDR", 0x2AAA)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x0055, 0)

	dict.sega("GEN_SET_ADDR", 0x5555)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x00A0, 0) --write byte command

	dict.sega("GEN_SET_ADDR", 0x0000)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0xAAAA, 0) --write data

	temp = dict.sega("GEN_ROM_RD", (0x0000>>1))
	local nak = 1
	while (temp ~= dict.sega("GEN_ROM_RD", (0x0000>>1))) do
		temp = dict.sega("GEN_ROM_RD", (0x0000>>1))
		print(help.hex(temp)) --"SE"
		nak = nak + 1 
	end
	temp = dict.sega("GEN_ROM_RD", (0x0000>>1))
	print("FINAL DATA", help.hex(temp)) --"SE"
	
	local addr = 0x0001
	local data = 0x5555
	print("write a byte", addr, data )
	dict.sega("GEN_SET_BANK", 0)
	dict.sega("GEN_SET_ADDR", 0x5555)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x00AA, 0)

	dict.sega("GEN_SET_ADDR", 0x2AAA)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x0055, 0)

	dict.sega("GEN_SET_ADDR", 0x5555)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x00A0, 0) --write byte command

	dict.sega("GEN_SET_ADDR", addr)
	dict.sega("GEN_FLASH_WR_ADDROFF", data, 0) --write data

	temp = dict.sega("GEN_ROM_RD", (addr))
	local nak = 1
	while (temp ~= dict.sega("GEN_ROM_RD", (addr))) do
		temp = dict.sega("GEN_ROM_RD", (addr))
		print(help.hex(temp)) --"SE"
		nak = nak + 1 
	end
	temp = dict.sega("GEN_ROM_RD", (addr))
	print("FINAL DATA", help.hex(temp)) --"SE"
	--]]


	--[[
	--read ram from wayne gretzky
	dict.sega("GEN_SET_BANK", 0x20>>1)
	temp = dict.sega("GEN_ROM_RD", (0x0000>>1))
	print(help.hex(temp)) --"SE"
	--print(string.char(temp>>8)) --"S"
	print(string.char(temp&0x00FF)) --"E"
	--temp = dict.sega("GEN_ROM_RD", (0x0002>>1))
	--print(help.hex(temp)) --"GA"
	----print(string.char(temp>>8)) --"G"
	--print(string.char(temp&0x00FF)) --"A"

	--dict.sega("GEN_SET_ADDR", 0x0000) --A16-1
	dict.sega("GEN_WR_LO", 0x0000, 0xAA) --A16-1
	temp = dict.sega("GEN_ROM_RD", (0x0000>>1))
	print(help.hex(temp)) --"SE"
	print(string.char(temp&0x00FF)) --"E"
	--]]


	--local valid = false
	local valid = true --force good
	-- Trailing spaces are required! Field length is 16 characters.
	if genesis_header["console_name"] == "SEGA GENESIS    " then valid = true end
	if genesis_header["console_name"] == "SEGA MEGA DRIVE " then valid = true end
	return valid
end


--dump the SEGA battery RAM starting at the provided bank
local function dump_ram( file, start_bank, ram_size_KB, debug )

	local KB_per_bank = 64 --128KByte addressable per bank, but only use lower byte of each 16bit word
	local addr_base = 0x00 --A15-8 address of ram start

--	--determine max ram per bank and base address
--	if (mapping == lorom_name) then
--		KB_per_bank = 32	-- LOROM has 32KB per bank
--		addr_base = 0x00	-- $0000 LOROM RAM start address
--	elseif (mapping == hirom_name) then
--		KB_per_bank = 8		-- HIROM has 8KB per bank
--		addr_base = 0x60	-- $6000 HIROM RAM start address
--	else
--		print("ERROR! mapping:", mapping, "not supported by dump_ram")
--	end
--
	local num_banks =1-- = ram_size_KB / KB_per_bank
--
--	--determine how much ram to read per bank
--    if ram_size_KB == nil then ram_size_KB = 0 end
--	if (ram_size_KB < KB_per_bank) then
--		num_banks = 1
--		KB_per_bank = ram_size_KB
--	else
--		num_banks = ram_size_KB / KB_per_bank
--	end
--
	local read_count = 0

	while ( read_count < num_banks ) do

		if debug then print( "dump RAM part ", read_count, " of ", num_banks) end

		--select desired bank
		--A17-23
		dict.sega("GEN_SET_BANK", start_bank+read_count)

	--	if (mapping == lorom_name) then --LOROM sram is inside /ROMSEL space
	--		dump.dumptofile( file, KB_per_bank, addr_base, "SNESROM_PAGE", false )
	--	else -- HIROM is outside of /ROMSEL space
	--		dump.dumptofile( file, KB_per_bank, addr_base, "SNESSYS_PAGE", false )
	--	end
	--
		--currently don't have means of dumping RAM with A16 high
		--dump.dumptofile(file, KB_per_bank/2, addr_base, "GENESIS_RAM_PAGE", debug) --A16 low
		dump.dumptofile(file, 8, addr_base, "GENESIS_RAM_PAGE", debug) --A16 low
--		dump.dumptofile(file, KB_per_bank/2, addr_base, "GENESIS_ROM_PAGE1", debug) --A16 high

		read_count = read_count + 1
	end

end

--write to the WRAM, assumes the WRAM was enabled/disabled as desired prior to calling
local function write_ram(file, ram_size_KB, debug)

--	init_mapper()

	--test some bytes
	--wr_prg_flash_byte(0x0000, 0xA5, true)
	--wr_prg_flash_byte(0x0FFF, 0x5A, true)

	print("\nProgramming battery SRAM")
	--initial testing of MMC3 with no specific MMC3 flash firmware functions 6min per 256KByte = 0.7KBps


	local base_addr = 0x0000 --writes occur $6000-7FFF
	local bank_size = 8*1024 --8KByte RAM chip
	local buff_size = 1      --number of bytes to write at a time
	local cur_bank = 0
--	local total_banks = ram_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata
	local rv
	local timout


	--while cur_bank < total_banks do

--		if (cur_bank %8 == 0) then
--			print("writting RAM bank: ", cur_bank, " of ", total_banks-1)
--		end

		--write the current bank to the mapper register
		--DATA writes written to $6000-7FFF
	--	dict.nes("NES_CPU_WR", 0x5113, cur_bank)	--PRG-RAM bank @ $6000-7FFF (regardless of PRG mode)
		dict.sega("GEN_SET_BANK", (0x20>>1))


		--program the entire bank's worth of data

		---[[  This version of the code programs a single byte at a time but doesn't require 
		--	MMC3 specific functions in the firmware
		--print("This is slow as molasses, but gets the job done")
		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size)
			data = string.unpack("B", byte_str, 1)

			--write the data
			--SLOWEST OPTION: no firmware MMC3 specific functions 100% host flash algo:
			--wr_prg_flash_byte(base_addr+byte_num, data, false)   --0.7KBps

			--need to quickly write the byte after unlocking the PRG-RAM
			--before the 11.2usec timeout happens
			rv = dict.sega("GEN_WR_LO", base_addr+byte_num, data) 

			--if (rv == data) then
			--	--write succeeded
			--	timeout = 0
			--else
			--	print("PRG-RAM byte failed to write, retrying")
			--	rv = dict.nes("MMC5_PRG_RAM_WR", base_addr+byte_num, data)  --3.8KBps (5.5x faster than above)
			--	if (rv ~= data) then
			--		print("FAILED on RETRY...")
			--	end
			--end

			byte_num = byte_num + 1
		end
		--]]

		--Have the device write a banks worth of data
		--FAST!  13sec for 512KB = 39KBps
		--flash.write_file( file, bank_size/1024, mapname, "PRGROM", false )
		--flash.write_file( file, bank_size/1024, "NOVAR", "PRGRAM", false )

--		cur_bank = cur_bank + 1
--	end

	print("Done Programming SAVE RAM")

end

--write a single byte to SNES ROM flash
--writes to currently selected bank address
local function wr_flash_byte(addr, value, debug)

	if (addr < 0x0000 or addr > 0xFFFF) then
		print("\n  ERROR! flash write to SEGA GENESIS", string.format("$%X", addr), "must be $0000-FFFF \n\n")
		return
	end

	--send unlock command and write byte
	--dict.snes("SNES_ROM_WR", 0x8AAA, 0xAA)
	--dict.snes("SNES_ROM_WR", 0x8555, 0x55)
	--dict.snes("SNES_ROM_WR", 0x8AAA, 0xA0)
	--dict.snes("SNES_ROM_WR", addr, value)

	if debug then print("write a byte", help.hex(addr), help.hex(value) ) end
	--dict.sega("GEN_SET_BANK", 0)
	dict.sega("GEN_SET_ADDR", 0x5555)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x00AA, 0)

	dict.sega("GEN_SET_ADDR", 0x2AAA)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x0055, 0)

	dict.sega("GEN_SET_ADDR", 0x5555)
	dict.sega("GEN_FLASH_WR_ADDROFF", 0x00A0, 0) --write byte command

	dict.sega("GEN_SET_ADDR", addr)
	dict.sega("GEN_FLASH_WR_ADDROFF", value, 0) --write value

--	temp = dict.sega("GEN_ROM_RD", (addr))
--	local nak = 1
--	while (temp ~= dict.sega("GEN_ROM_RD", (addr))) do
--		temp = dict.sega("GEN_ROM_RD", (addr))
--		print(help.hex(temp)) --"SE"
--		nak = nak + 1 
--	end
--	temp = dict.sega("GEN_ROM_RD", (addr))
--	print("FINAL DATA", help.hex(temp)) --"SE"

	local rv = dict.sega("GEN_ROM_RD", (addr))

	local i = 0

	while ( rv ~= value ) do
		rv = dict.sega("GEN_ROM_RD", (addr))
		--if debug then print("post write read:", help.hex(rv)) end
		i = i + 1
		if i > 20 then
			print("failed write, tried:", string.format("%X",value), "read back value:", string.format("%X",rv))
			return
		end
	end
	if debug then print(i, "naks, done writing byte.") end
	if debug then print("written value:", string.format("%X",value), "verified value:", string.format("%X",rv)) end

	--TODO handle timeout for problems

	--TODO return pass/fail/info
end


local function flash_rom(file, rom_size_KB, debug)

	print("\nProgramming ROM flash")

	--test some bytes
--	dict.sega("GEN_SET_BANK", 0x00) wr_flash_byte(0x0000, 0xAAAA, true) wr_flash_byte(0x0001, 0x5555, true)
--	dict.sega("GEN_SET_BANK", 0x00) wr_flash_byte(0x0002, 0x0000, true) wr_flash_byte(0x0003, 0xC3C3, true)
--	dict.sega("GEN_SET_BANK", 0x00) wr_flash_byte(0x0004, 0xDEAD, true) wr_flash_byte(0x0005, 0xBEEF, true)
--	dict.sega("GEN_SET_BANK", 0x00) wr_flash_byte(0x0006, 0x3333, true) wr_flash_byte(0x0007, 0xCCCC, true)
--	--last of 512KB
--	if true then return end

	--most of this is overkill for NROM, but it's how we want to handle things for bigger mappers
	local base_addr = 0x0000
	local bank_size = 2*64*1024 --2Bytes per address, 64K addresses
	local buff_size = 1      --number of bytes to read from file at a time
	local cur_bank = 0

--	if (mapping==lorom_name) then
--		base_addr = 0x8000 --writes occur $8000-FFFF
--		bank_size = 32*1024 --SNES LOROM 32KB per ROM bank
--	elseif (mapping==hirom_name) then
--		base_addr = 0x0000 --writes occur $0000-FFFF
--		bank_size = 64*1024 --SNES HIROM 64KB per ROM bank
--	else
--		print("ERROR!! mapping:", mapping, "not supported")
--	end

	local total_banks = rom_size_KB*1024/bank_size

	local byte_num --byte number gets reset for each bank
	local byte_str, data, readdata

	while cur_bank < total_banks do

		if (cur_bank %4 == 0) then
			print("writting ROM bank: ", cur_bank, " of ", total_banks-1)
		end

		--select the current bank
		if (cur_bank <= 0x7F) then
			--dict.sega("GEN_SET_BANK", (cur_bank>>1)) --genesis bank is off by 1 due to lack of A0
			dict.sega("GEN_SET_BANK", (cur_bank)) --Don't think that's acutally true this bank is true INLretro bank
		else
			print("\n\nERROR!!!!  SEGA bank cannot exceed 0x7F, it was:", string.format("0x%X",cur_bank))
			return
		end


		--program the entire bank's worth of data

		---[[  This version of the code programs a single byte at a time but doesn't require
		--	board specific functions in the firmware
		print("This is slow as molasses, but gets the job done")

		--SET ADDR so FLASH_WR_ADDROFF works
		dict.sega("GEN_SET_ADDR", 0xFFFF)

		byte_num = 0  --current byte within the bank
		while byte_num < bank_size do

			--read next byte from the file and convert to binary
			byte_str = file:read(buff_size) --high byte
			data = string.unpack("B", byte_str, 1)
			--print(help.hex(data))
			data = data<<8
			--print(help.hex(data))
			byte_str = file:read(buff_size) --low byte
			data = data + string.unpack("B", byte_str, 1)
			--print(help.hex(data))

			--write the data
			--SLOWEST OPTION: no firmware specific functions 100% host flash algo:
			--wr_flash_byte(((base_addr+byte_num)>>1), data, false)   --0.7KBps
			--EASIEST FIRMWARE SPEEDUP: 5x faster, create firmware write byte function:
			dict.sega("GEN_SST_FLASH_WR_ADDROFF", data, 1) 

			--if (verify) then
			--	readdata = dict.nes("NES_CPU_RD", base_addr+byte_num)
			--	if readdata ~= data then
			--		print("ERROR flashing byte number", byte_num, " in bank",cur_bank, " to flash ", data, readdata)
			--	end
			--end

			byte_num = byte_num + 2 --2 Bytes per write
		end
		--]]

		--Have the device write a banks worth of data
	--	if (mapping == lorom_name) then
	--		flash.write_file( file, bank_size/1024, "LOROM_3VOLT", "SNESROM", false )
	--	else
	--		flash.write_file( file, bank_size/1024, "HIROM_3VOLT", "SNESROM", false )
	--	end

		--flash.write_file( file, bank_size/1024, "HIROM_3VOLT", "GENESISROM", false )
		--TODO define different flash part types
		--flash.write_file( file, bank_size/1024, 0, "GENESISROM", false )

		cur_bank = cur_bank + 1
	end

	print("Done Programming ROM flash")

end

--Cart should be in reset state upon calling this function 
--this function processes all user requests for this specific board/mapper
local function process(process_opts, console_opts)
	local file 

	-- Use specified ram size if provided, otherwise autodetect.
	local ram_size = console_opts["wram_size_kb"]
	local ramdumpfile = process_opts["dumpram_filename"]
	--local flashfile = process_opts["flash_filename"]
	local flashfile = process_opts["flash_filename"]
	local verifyfile = process_opts["verify_filename"]
	local rom_size = console_opts["rom_size_kbyte"]

    -- Initialize device i/o for SEGA
	dict.io("IO_RESET")
	dict.io("SEGA_INIT")
	local genesis_header = read_header()

	if process_opts["test"] then
		-- If garbage data is in the header, it's a waste of time trying to proceed doing anything else.
		local valid_header = test(genesis_header)
		if valid_header ~= true then print("Unreadable cartridge - exiting! (Try cleaning cartridge connector?)") end
		assert(valid_header)
		print_header(genesis_header)
	end

	-- TODO: dump the ram to file 
	if process_opts["dumpram"] then
		--unsupported("dumpram")
		print("dumping save RAM")


		file = assert(io.open(ramdumpfile, "wb"))

		--dump cart into file
		local rambank = (0x20>>1) --A17-23 wayne gretsky RAM starts at bank $20>>1

		dump_ram(file, rambank, ram_size, true)

		--may disable SRAM by placing /RESET low

		--close file
		assert(file:close())

		print("DONE Dumping SAVE RAM")
	end

	-- Dump the cart to dumpfile.
	if process_opts["read"] then
		
		-- If ROM size wasn't provided, attempt to use value in internal header.
		local rom_size = console_opts["rom_size_kbyte"]
		if rom_size == 0 then
			print("ROM Size not provided, " .. str_rom_size(genesis_header["rom_size"]) .. " detected.")
			rom_size = genesis_header["rom_size"]
		end

		print("\nDumping SEGA ROM...")
		file = assert(io.open(process_opts["dump_filename"], "wb"))
		
		--dump cart into file
		dump_rom(file, rom_size, false)

		--close file
		assert(file:close())
		print("DONE Dumping SEGA ROM")
		print("Computing checksum...")
		local checksum = checksum_rom(process_opts["dump_filename"])
		if checksum == genesis_header["checksum"] then
			print("CHECKSUM OK! DUMP SUCCESS!")
		else
			print("CHECKSUM MISMATCH - BAD DUMP! (Try cleaning cartridge connector?)")
		end
	end

	if process_opts["erase"] then
	--	unsupported("erase")
		--erase the cart
		print("erasing SST flash cart")
		dict.sega("GEN_SET_BANK", 0)
		dict.sega("GEN_SET_ADDR", 0x5555)
		dict.sega("GEN_FLASH_WR_ADDROFF", 0x00AA, 0)
	
		dict.sega("GEN_SET_ADDR", 0x2AAA)
		dict.sega("GEN_FLASH_WR_ADDROFF", 0x0055, 0)
	
		dict.sega("GEN_SET_ADDR", 0x5555)
		dict.sega("GEN_FLASH_WR_ADDROFF", 0x0080, 0) --ERASE
	
		dict.sega("GEN_SET_ADDR", 0x5555)
		dict.sega("GEN_FLASH_WR_ADDROFF", 0x00AA, 0) --ERASE
	
		dict.sega("GEN_SET_ADDR", 0x2AAA)
		dict.sega("GEN_FLASH_WR_ADDROFF", 0x0055, 0) --ERASE
	
		dict.sega("GEN_SET_ADDR", 0x5555)
		dict.sega("GEN_FLASH_WR_ADDROFF", 0x0010, 0) --ERASE
	
	
		temp = dict.sega("GEN_ROM_RD", (0))
		local nak = 1
		while (temp ~= dict.sega("GEN_ROM_RD", (0))) do
			temp = dict.sega("GEN_ROM_RD", (0))
			--print(help.hex(temp)) --"SE"
			nak = nak + 1 
		end
		temp = dict.sega("GEN_ROM_RD", (0))
		print("DONE ERASING, FINAL DATA", help.hex(temp)) --"SE"
	end

	-- TODO: write to wram on the cart
	--if writeram then
	if process_opts["writeram"] then
		--unsupported("writeram")
		print("\nWritting to WRAM...")

		file = assert(io.open(process_opts["writeram_filename"], "rb"))
		--write_ram(file, ram_size_KB, debug)
		write_ram(file, ram_size, true)
		
		assert(file:close())

		print("DONE Writting WRAM")
	end

	-- TODO: program flashfile to the cart
	if process_opts["program"] then
		--unsupported("program")

		--open file
		file = assert(io.open(flashfile, "rb"))
		--determine if auto-doubling, deinterleaving, etc,
		--needs done to make board compatible with rom

		--flash cart
		flash_rom(file, rom_size, true)

		--close file
		assert(file:close())
	end

	-- TODO: verify flashfile is on the cart
	if process_opts["verify"] then
		unsupported("verify")
	end

	dict.io("IO_RESET")
end


-- global variables so other modules can use them
--    NONE

-- call functions desired to run when script is called/imported
--    NONE

-- functions other modules are able to call
genesis_v2.process = process

-- return the module's table
return genesis_v2
