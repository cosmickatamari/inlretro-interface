
-- create the module's table
local help = {}

-- import required modules
--local dict = require "scripts.app.dict"

-- file constants

-- local functions
local function hex(data)
	return string.format("%X", data)
end

-- file must already be open for writting in binary mode
local function file_wr_bin(file, data)
	file:write(string.char( data ))
end


-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
help.hex = hex
help.file_wr_bin = file_wr_bin

-- return the module's table
return help
