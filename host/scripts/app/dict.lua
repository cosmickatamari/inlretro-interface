-- dictionary module
-- creates tables with dictionary entries from shared\shared_dict*.h files
-- performs usb transfer when making dictionary call and returns device data

-- create the module's table
local dict = {}

-- file constants
local USB_IN = 0x80	--device to host
local USB_OUT = 0x00	--host to device

-- read all the C shared_dict*.h files and create tables with all values
-- This isn't 'Nam there are rules!
-- dictionary #define that start with underscore are skipped this skips over header and special cases
-- currently only finds lowercase #define statements (seems C does too!)
-- multiline comments /* comment */ are not permitted, will throw error!
-- #define statements must have a numeric value such as: #define FOO 4
-- #define without number will error like this: "#define FOO BAR" or "#define FOO BAR - 100" is bad too!
-- fills passed in table with keys and values to be used for making usb dictionary calls
-- accepts decimal or hex when 0x00 format
-- trailing underscores are trimmed, this allows firmware macro defines to match dictionary defines
-- sets "opcode_rlen" when RL=<number> (ie RL = 5) in the comments following the opcode
local function create_dict_tables( table, file )
	assert(io.input(file, "r"))

	local count = 0
	local define = 0
	local define_end = 0
	local slash = 0
	local line 
	local comment
	for line in io.lines() do
		count = count + 1
		comment = nil	--needs cleared for each pass
		--search for multiline comment opening, starting at index 1, plain search = true
		if string.find( line, "/*", 1, true) then
			print("\n\n!!!ERROR!!!\nmultiline comment found line number", count)
			print("while parsing file:", file, "\nonly inline comments are permitted!!!\n")
			error("multiline comments not allowed in dictionary files!")
		end
		define, define_end = string.find( line, "#define") 
		if define then 
			slash = string.find(line, "//")
			--check for comment following define, if present cut out comment
			if slash and (slash>define) then
				--store comment contents for later parsing
				comment = string.sub(line, slash, -1)
				line = string.sub(line, 1, slash-1 )
			end
			--check for comment prior to define, skip if present
			if not (slash and (slash<define)) then 
				--print( count, define, line) 
				line = string.sub(line, define_end+1, -1)
				--match alpha and any trailing printable chars besides white space
				--this doesn't match guarded header/footer that starts with underscore
				local key = string.match( line, "%s%a%g+" )
				if key then
--	print ("\n\n",line)
					--key found, trim key from line
					local key_start, key_end
					key_start, key_end = string.find( line, key )
					line = string.sub( line, key_end+1, -1)
					--trim preceeding space needed to filter out underscore
					key = string.match( key, "%a%g+" )
					--trim any trailing underscore, trick that allows firmware to call macro with "same" macro
					if( (key:sub(-1,-1)) == '_' ) then
						key = key:sub(1,-2)
					end
					--match the number
					if string.match( line, "[^%s0-9a-fxA-F]+") then
			print("\n\n!!!ERROR!!!\ndictionary file #define parsing problem line:", count)
			print("while parsing file:", file, "\n", line, "is not a number!!!\n")
						error("dictionary #define statements must end with a number")
					end

					local number = string.match( line,  "%s+[0-9a-fxA-F]+")
					if number then
						number = string.match( number, "%s+[0-9a-fxA-F]+")
					end
--	print (number)
					--at this point we have the key and value, just convert from string
					number = tonumber( number )
--	print("key/val:", key, number)
--	print("key type:", type(key), "value type:", type(number))
					--add the key and value pair to the table
					table[key] = number

					--now process comment to find extra dictionary values stored in comments
--	print(comment)
					if comment then
						--return length "rlen" is set by RL=number (ie RL=10, RL=-0x100, etc)
						--positive RL denotes endpoint IN, negative denotes endpoint OUT
						--first match positive values
						local rlen = string.match( comment, "%s*RL%s*=%s*[0-9a-fA-Fx]+")
						if (rlen) then
							--trim RL= portion
							rlen = string.match( rlen, "[0-9a-fA-Fx]+")
							rlen = tonumber( rlen )
							--add return length to table
							table[key.."rlen"] = rlen;
						end
						--next check for negative values
						rlen = string.match( comment, "%s*RL%s*=%s*-%s*[0-9a-fA-Fx]+")
						if (rlen) then
							--trim RL=- portion
							rlen = string.match( rlen, "[0-9a-fA-Fx]+")
							rlen = - tonumber( rlen )
							--add return length to table
							table[key.."rlen"] = rlen;
						end
					end
--	print(key, ": val/rlen:", table[key], table[key.."rlen"], "\n\n")

				end
			end
		end
	end
end

--determine endpoint & wLength for usb transfer
--default is ep=IN, rlen=1 if different than those values it must be defined in dictionary
--positive values are associated with ep IN, negative ep OUT
local function default_rlen_1_in( rlen )

	local ep
	if rlen then
		--RL defined in dictionary
		if rlen < 1 then
			ep = USB_OUT
			rlen = -rlen
		else
			ep = USB_IN
		end
	else	--RL not defined, assume default
		ep = USB_IN
		rlen = 1
	end

	return rlen, ep

end

-- TODO look closer at binary data packing/unpacking functions
local function string_to_int( string, numbytes)

	local i = 0
	local rv = 0
	while i < numbytes do
		rv = rv | (string:byte(i+1) << 8*i)
		i = i+1
	end

	return rv

end

RETURN_ERR_IDX = 1
RETURN_LEN_IDX = 2
RETURN_DATA = 3


-- external call for pinport dictionary
local function pinport( opcode, operand, misc, data )

	assert ( op_pinport[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_pinport.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_pinport[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_pinport.h")
		--decode string operands into 
		operand = op_pinport[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_pinport[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_PINPORT"], ( misc<<8 | op_pinport[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 


end

-- external call for io dictionary
local function io( opcode, operand, misc, data )

	assert ( op_io[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_io.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_io[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_io.h")
		--decode string operands into 
		operand = op_io[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_io[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_IO"], ( misc<<8 | op_io[opcode]),	operand,	wLength,	data)

	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 


end

-- external call for nes dictionary
local function nes( opcode, operand, misc, data, test_opcode )

	assert ( op_nes[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_nes.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_nes[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_game.h")
		--decode string operands into 
		operand = op_nes[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_nes[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_NES"], ( misc<<8 | op_nes[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	--hack to test if running old firmware version for NESmaker legacy compatability
	if test_opcode then
		--just want to report if opcode succeeded or not
		if error_code == err_codes["SUCCESS"] then
			return true
		else
			return false
		end
	end
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 


end


-- external call for snes dictionary
local function snes( opcode, operand, misc, data )

	assert ( op_snes[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_snes.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_snes[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_snes.h")
		--decode string operands into 
		operand = op_snes[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_snes[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_SNES"], ( misc<<8 | op_snes[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 


end

-- external call for gameboy dictionary
local function gameboy( opcode, operand, misc, data )

	assert ( op_gameboy[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_gameboy.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_gameboy[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_gameboy.h")
		--decode string operands into 
		operand = op_gameboy[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_gameboy[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_GAMEBOY"], ( misc<<8 | op_gameboy[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 


end


-- external call for gba dictionary
local function gba( opcode, operand, misc, data )

	assert ( op_gba[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_gba.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_gba[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_gba.h")
		--decode string operands into 
		operand = op_gba[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_gba[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_GBA"], ( misc<<8 | op_gba[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 


end


-- external call for sega dictionary
local function sega( opcode, operand, misc, data )

	assert ( op_sega[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_sega.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_sega[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_sega.h")
		--decode string operands into 
		operand = op_sega[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_sega[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_SEGA"], ( misc<<8 | op_sega[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 


end


-- external call for n64 dictionary
local function n64( opcode, operand, misc, data )

	assert ( op_n64[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_n64.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_n64[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_n64.h")
		--decode string operands into 
		operand = op_n64[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_n64[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_N64"], ( misc<<8 | op_n64[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 


end

-- external call for swim dictionary
local function swim( opcode, operand, misc, data )

	assert ( op_swim[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_swim.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_swim[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_swim.h")
		--decode string operands into 
		operand = op_swim[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_swim[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_SWIM"], ( misc<<8 | op_swim[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
RETURN_ACK_IDX = 3
RETURN_DAT_IDX = 4
	if data_len then
		--return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
		error_code = data:byte(RETURN_ACK_IDX)
		data_len =   data:byte(RETURN_DAT_IDX)
		return error_code, data_len
	else 
		return nil
	end 


end

-- external call for jtag dictionary
local function jtag( opcode, operand, misc, data )

	assert ( op_jtag[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_jtag.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_jtag[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_jtag.h")
		--decode string operands into 
		operand = op_jtag[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_jtag[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_JTAG"], ( misc<<8 | op_jtag[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 



end

-- external call for bootload dictionary
local function bootload( opcode, operand, misc, data, permiterror )

	assert ( op_bootload[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_bootload.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_bootload[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_bootload.h")
		--decode string operands into 
		operand = op_bootload[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_bootload[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_BOOTLOAD"], ( misc<<8 | op_bootload[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	if not permiterror then
		assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)
	else
		--called with permission of error
		if error_code ~= err_codes["SUCCESS"] then
			print("Permitted Error with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)
		end
	end

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 



end



-- external call for firmware update dictionary
local function fwupdate( opcode, operand, misc, data )

	assert ( op_fwupdate[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_fwupdate.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_fwupdate[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_fwupdate.h")
		--decode string operands into 
		operand = op_fwupdate[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_fwupdate[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_FWUPDATE"], ( misc<<8 | op_fwupdate[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 



end


-- external call for ciccom dictionary
local function ciccom( opcode, operand, misc, data )

	assert ( op_ciccom[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_ciccom.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_ciccom[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_ciccom.h")
		--decode string operands into 
		operand = op_ciccom[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_ciccom[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_CICCOM"], ( misc<<8 | op_ciccom[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 



end


-- external call for misc dictionary
local function stuff( opcode, operand, misc, data )

	assert ( op_stuff[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_stuff.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_stuff[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_stuff.h")
		--decode string operands into 
		operand = op_stuff[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_stuff[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     wIndex	wLength	 		data
		ep, dict["DICT_STUFF"], ( misc<<8 | op_stuff[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 



end




local function buffer_payload_in( wLength, buff_num )

	local opcode = nil
	local data = nil
	if not buff_num then 
		opcode = op_buffer["BUFF_PAYLOAD"] 
	else
		opcode = op_buffer["BUFF_PAYLOAD0"] + buff_num 
	end
	
	local count
	count, data = usb_vend_xfr( 
		USB_IN, dict["DICT_BUFFER"],	opcode,		0,	wLength,	nil)

	assert ( (count == wLength ), ("ERROR!!! device only sent:"..count.."bytes, expecting:"..wLength))

	--return the retrieved string
	return data

end

local function buffer_payload_out( num_bytes, data, buff_num )

	local opcode = nil

	local wLength = 0
	if num_bytes == 256 then
		--2B in setup packet
		operand = string.unpack("B", data ,1) | (string.unpack("B", data ,2)<<8)
--		print(string.format("%04X ", operand))
		--operand = string.sub(data, 1, 2)
		wLength = 254
		if not buff_num then 
			opcode = op_buffer["BUFF_OUT_PAYLOAD_2B_INSP"] 
			buff_num = 0
		else
			opcode = op_buffer["BUFF_OUT_PAYLOADN_2B_INSP"]
		end
	else	--don't stuff data in setup packet
		wLength = num_bytes
		operand = 0
		if not buff_num then 
			opcode = op_buffer["BUFF_PAYLOAD"] 
			buff_num = 0
		else
			opcode = op_buffer["BUFF_PAYLOAD0"] + buff_num 
			buff_num = 0	--these opcodes don't put buff num in miscdata, but should update them to do so.
		end
	end

	local count
	count, data = usb_vend_xfr( 
		USB_OUT, ((buff_num<<8) | dict["DICT_BUFFER"]),	opcode,		operand,	wLength,	data:sub(3,-1))

	assert ( (count == wLength ), ("ERROR!!! host only sent:"..count.."bytes, expecting:"..wLength))

	return 

end

-- external call for buffer dictionary
local function buffer( opcode, operand, misc, data, stringout )

	assert ( op_buffer[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_buffer.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_buffer[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_buffer.h")
		--decode string operands into 
		operand = op_buffer[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_buffer[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     	wIndex		wLength		data
		ep, dict["DICT_BUFFER"], ( misc<<8 | op_buffer[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if stringout then
		return data:sub(RETURN_DATA, data_len+RETURN_DATA)
	elseif data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 


end

-- external call for operation dictionary
local function operation( opcode, operand, misc, data )

	assert ( op_operation[opcode] , "\nERROR undefined opcode: " .. opcode .. " must be defined in shared_dict_operation.h")

	if not operand then 
		operand = 0 
	elseif type(operand) == "string" then
		assert ( op_operation[operand] ,"\nERROR undefined operand: " .. operand .. " must be defined in shared_dict_operation.h")
		--decode string operands into 
		operand = op_operation[operand]
	end
	
	if not misc then misc = 0 end

	local wLength, ep = default_rlen_1_in(op_operation[opcode.."rlen"])

	local count
	count, data = usb_vend_xfr( 
	--	ep,	dictionary		wValue[misc:opcode]     	wIndex		wLength		data
		ep, dict["DICT_OPER"], ( misc<<8 | op_operation[opcode]),	operand,	wLength,	data)
	--print(count)
	local error_code, data_len
	if ep == USB_IN then
		error_code = data:byte(RETURN_ERR_IDX)
		data_len =   data:byte(RETURN_LEN_IDX)
	end
	--print("error:", error_code, "data_len:",  data_len)
	
	assert ( (error_code == err_codes["SUCCESS"]), "\n ERROR!!! problem with opcode: " .. opcode .. " operand: " .. operand .. " misc: " .. misc .. " device error code: " .. error_code)

	if data_len and data_len ~= (wLength - RETURN_LEN_IDX) then
		print("WARNING!! Device's return data length:", data_len, "did not match expected:", wLength-RETURN_LEN_IDX)
	end

	--process the return data string and return it to calling function
	if data_len then
		return string_to_int( data:sub(RETURN_DATA, data_len+RETURN_DATA), data_len) 
	else 
		return nil
	end 


end

-- Dictionary table definitions
-- global so other modules can use them
dict = {}
op_pinport = {}
op_buffer = {}
op_io = {}
op_operation = {}
op_nes = {}
op_snes = {}
op_gameboy = {}
op_gba = {}
op_sega = {}
op_n64 = {}
op_swim = {}
op_jtag = {}
op_bootload = {}
op_fwupdate = {}
op_ciccom = {}
op_stuff = {}
err_codes = {}

-- Dictionary table definitions initialized by calling parser
-- call functions desired to run when script is called
create_dict_tables( dict, 	"../shared/shared_dictionaries.h")
create_dict_tables( op_pinport, "../shared/shared_dict_pinport.h")
create_dict_tables( op_buffer, 	"../shared/shared_dict_buffer.h")
create_dict_tables( op_io,  	"../shared/shared_dict_io.h")
create_dict_tables( op_operation,  "../shared/shared_dict_operation.h")
create_dict_tables( op_nes,  	"../shared/shared_dict_nes.h")
create_dict_tables( op_snes,  	"../shared/shared_dict_snes.h")
create_dict_tables( op_gameboy,  	"../shared/shared_dict_gameboy.h")
create_dict_tables( op_gba,  	"../shared/shared_dict_gba.h")
create_dict_tables( op_sega,  	"../shared/shared_dict_sega.h")
create_dict_tables( op_n64,  	"../shared/shared_dict_n64.h")
create_dict_tables( op_swim,  	"../shared/shared_dict_swim.h")
create_dict_tables( op_jtag,  	"../shared/shared_dict_jtag.h")
create_dict_tables( op_bootload,"../shared/shared_dict_bootload.h")
create_dict_tables( op_fwupdate,"../shared/shared_dict_fwupdate.h")
create_dict_tables( op_ciccom,	"../shared/shared_dict_ciccom.h")
create_dict_tables( op_stuff,	"../shared/shared_dict_stuff.h")
create_dict_tables( err_codes, 	"../shared/shared_errors.h")

-- functions other modules are able to call
dict.pinport = pinport
dict.io = io
dict.nes = nes
dict.snes = snes
dict.gameboy = gameboy
dict.gba = gba
dict.sega = sega
dict.n64 = n64
dict.swim = swim
dict.jtag = jtag
dict.bootload = bootload
dict.ciccom = ciccom
dict.buffer = buffer
dict.buffer_payload_in = buffer_payload_in
dict.buffer_payload_out = buffer_payload_out
dict.operation = operation
dict.fwupdate = fwupdate
dict.stuff = stuff
dict.op_buffer = op_buffer

-- return the module's table
return dict

