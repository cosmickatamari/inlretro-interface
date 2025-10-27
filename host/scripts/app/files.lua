
-- create the module's table
local files = {}

-- import required modules
local help = require "scripts.app.help"

-- file constants

-- local functions

-- file must already be open for writting in binary mode
-- read from something like the cart and get a number
-- send that number here to write to the file in binary (interpret as an ascii char)
local function wr_bin_byte(file, data)
	data = data & 0x00FF --negative and overly large ints need trimmed to 8bits
	file:write(string.char( data ))
end

--always forget how to read a byte from a file even though it's super simple...
--file must already be open for reading in binary mode
local function rd_bin_byte(file, debug)

	--TODO test & support reading more than 1 byte
	local num_bytes = 1

	return string.byte(file:read(num_bytes))
end

--compare the two files return true if identical
--files should be closed prior to calling, files are closed after compared
local function compare(filename1, filename2, size_must_equal, debug)


	file1 = assert(io.open(filename1, "rb"))
	file2 = assert(io.open(filename2, "rb"))

	local byte_str1
	local byte_str2

	local buffsize = 1
	local byte_num = 0

	local rv = true

	while true do	--exit when end of file 1 reached

		--read next byte from the file and convert to binary
		--gotta be a better way to read a half word (16bits) at a time but don't care right now...
		byte_str1 = file1:read(buffsize)
		byte_str2 = file2:read(buffsize)

		if byte_str1 and byte_str2 then
			--compare byte string from each file

			if byte_str1 == byte_str2 then
				--bytes matched count the bytes
				byte_num = byte_num + 1
				--print(filename1, "was:", help.hex(data1), filename2, "was:", help.hex(data2))
			else
				local data1 = string.unpack("B", byte_str1, 1)
				local data2 = string.unpack("B", byte_str2, 1)
				print("failed to verify byte number:", string.format("0x%X", byte_num))
				print(filename1, "was:", help.hex(data1), filename2, "was:", help.hex(data2))
				rv = false
				break
			end
		
		elseif byte_str1 and not byte_str2 then
			print("end of file:", filename2, "reached, it's smaller than", filename1 )
			if size_must_equal then
				print("files were not the same size")
				rv = false
			else
				rv = "FILE2 larger than FILE1"
			end
			break
		elseif byte_str2 and not byte_str1 then
			print("end of file:", filename1, "reached, it's smaller than", filename2 )
			if size_must_equal then
				print("files were not the same size")
				rv = false
			else
				rv = "FILE1 larger than FILE2"
			end
			break
		else
			--end of both files reached, they must have matched
			break
			rv = true
		end

	end


	--close the files
	assert(file1:close())
	assert(file2:close())

	return rv

end

--reads file until finds a line that includes the token string
--the line with the token is consumed, the next line that you read from the 
--file will be the line that follows the line with the token
--Created to find L00000 line in jedec files
--RETURN: the line in string format that matched the token
--addition of returning the string allows for verification of the user code
local function readtill_line(file, token, debug)

	--local temp = string.byte(file:read(10))
	local temp_line = "notnil" --= file:read("*line")
	local line_num = 0
	if debug then print("finding:", token) end

	--while line_num < 100 do
	local found_token = false
	while not found_token do

		temp_line = file:read("*line")
		line_num = line_num + 1
	--	if debug then print("line num", line_num, "reads:", temp_line) end

		if temp_line then
			if string.find(temp_line, token) then
				if debug then print("found token in line num", line_num, "reads:", temp_line) end
				found_token = true
			end
		else	
			print("reached end of file, could not find token", token)
			return nil
		end

	end
--	temp = file:read("*line")
--	if debug then print("next line:", temp) end

	return temp_line

end

local function nextline(file)
	return file:read("*line")
end

--read 3 lines from jedec file and convert from binary to hex string
--input:
--10111111111001111111000111111111111111111111111111111110001111110000111110100000
--00011110110000110001100010000111111111111000110001111100000111111111100000111111
--111111111111
--output:
--FFFFC1FF83E31FFE118C37805F0FC7FFFFFFF8FE7FD
local function jedec_3ln_2hexstr(file, debug)
	local line1 = nextline(file)
	local line2 = nextline(file)
	local line3 = nextline(file)
	if debug then print(line1) print(line2) print(line3) end

	local line1_len = string.len(line1) - 1
	local line2_len = string.len(line2) - 1
	local line3_len = string.len(line3) - 1
	--these strings have extra newline character at the end
	if debug then print("line 1,2,3 lengths:", line1_len, line2_len, line3_len) end

	line1 = string.sub(line1, 1, line1_len)
	line2 = string.sub(line2, 1, line2_len)
	line3 = string.sub(line3, 1, line3_len)
	if debug then print(line1) print(line2) print(line3) end

	--contatenate all the lines together
	--local padding = "1111" -- 172bits = 22.5 Bytes, pad with extra "F"
	local padding = "" -- 172bits = 43 Nibbles no padding needed
	local bin_line = padding .. line1 .. line2 .. line3
	local bin_len = line1_len + line2_len + line3_len + string.len(padding)
	if debug then print("bin len", bin_len, "bin data", bin_line) end

--	print(tonumber(line3,2))

	--create a hex string that starts with last bit from 3rd line
	local temp_nibble
	local hex_str = ""
	while bin_len > 0 do
		--need to reverse the bit order
		--temp_nibble = string.sub(bin_line, bin_len, bin_len) .. 
		--		string.sub(bin_line, bin_len-1, bin_len-1) ..
		--		string.sub(bin_line, bin_len-2, bin_len-2) ..
		--		string.sub(bin_line, bin_len-3, bin_len-3)
		temp_nibble = string.reverse(string.sub(bin_line, bin_len-3, bin_len))

		--temp_nibble = tonumber(string.sub(bin_line, bin_len-3, bin_len), 2) --2 is base (binary)
		temp_nibble = tonumber(temp_nibble, 2) --2 is base (binary)
		if debug then print("decimal", temp_nibble) end
		temp_nibble =string.format("%1.1X", temp_nibble)
		hex_str = hex_str .. temp_nibble
		if debug then print("hex", temp_nibble) end
		bin_len = bin_len - 4
	end

	if debug then print("hex string:", hex_str) end
	
	return hex_str
end

-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
files.compare = compare
files.wr_bin_byte = wr_bin_byte
files.rd_bin_byte = rd_bin_byte
files.readtill_line = readtill_line
files.nextline = nextline
files.jedec_3ln_2hexstr = jedec_3ln_2hexstr

-- return the module's table
return files
