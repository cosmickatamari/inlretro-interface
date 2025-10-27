
-- create the module's table
local buffers = {}

-- import required modules
local dict = require "scripts.app.dict"

-- file constants

-- local functions

-- Desc:allocate buffers on device
-- Pre: buffers must be reset
-- Post:All buffers and raw sram unallocated
--	Sets id, status to EMPTY, and last_idx.
--	sets reload to sum of buffers
--	All other elements set to zero
-- Rtn: SUCCESS if no errors
local function allocate( num_buffers, buff_size )
--
--	//TODO verify number of banks doesn't exceed devices' configuration
--//	uint8_t rv[RV_DATA0_IDX];
--//	uint8_t rv;
	local rv = nil

--	//want to allocate buffers as makes sense based on num and size
--	//Ideally a buffer will be 256Bytes which equals a page size
--	//256Bytes doesn't work well with dumping though as max xfr size is 254Bytes
--	//So for simplicity dumping starts with 128B buffers
--	//But this means a single buffer can't hold a full page
--	//In this case the missing bits between buffer size and page_num must be contained
--	//in upper bits of the buffer id.

	local buff0basebank = 0
	local numbanks = buff_size/ (dict.op_buffer["RAW_BANK_SIZE"])
	--numbanks= buff_size/RAW_BANK_SIZE;
	local buff1basebank = numbanks	--//buff1 starts right after buff0

	local buff0id = 0
	local buff1id = 0
	local reload = 0
	local buff0_firstpage = 0
	local buff1_firstpage = 0

--	if( (num_buffers == 2) && (buff_size == 128)) {
	if( (num_buffers == 2) and (buff_size == 128)) then
--	//buff0 dumps first half of page, buff1 dumps second half, repeat
--		//MSB tells buffer value of A7 when operating
		buff0id = 0x00
		buff1id = 0x80
--	//set reload (value added to page_num after each load/dump to sum of buffers
--	// 2 * 128 = 256 -> reload = 1
		reload = 0x01
--	//set first page
		buff0_firstpage = 0x0000
		buff1_firstpage = 0x0000
--
--	} else if( (num_buffers == 2) && (buff_size == 256)) {
	elseif  ( (num_buffers == 2) and (buff_size == 256)) then
--	//buff0 dumps even pages, buff1 dumps odd pages
--		//buffer id not used for addressing both id zero for now..
		buff0id = 0x00
		buff1id = 0x00
--
--	//set reload (value added to page_num after each load/dump to sum of buffers
--	// 2 * 256 = 512 -> reload = 2
		reload = 0x02;
--	//set first page of each buffer
		buff0_firstpage = 0x0000;
		buff1_firstpage = 0x0001;

	else
--		//don't continue
		print("ERROR! Not setup to handle this buffer config");
		return nil
	end


--	//allocate buffer0
	dict.buffer("ALLOCATE_BUFFER0", ((buff0id<<8)|(buff0basebank)),	numbanks)	
--	//allocate buffer1
	dict.buffer("ALLOCATE_BUFFER1", ((buff1id<<8)|(buff1basebank)),	numbanks)	

--	//set first page and reload (value added to page_num after each load/dump to sum of buffers
--	//set buffer0
	dict.buffer("SET_RELOAD_PAGENUM0", buff0_firstpage, reload)
--	//set buffer1
	dict.buffer("SET_RELOAD_PAGENUM1", buff1_firstpage, reload)

	return true

end

-- pass in table buffer numbers would like to wait on
-- pass in table of status waiting on for all buffers
local function status_wait( buff_nums, end_status, debug )


	local rv = nil
	for key_buff, buff in pairs(buff_nums) do
		rv = nil
		if debug then print("buffer wait:", key_buff, buff) end
		while rv ~= "EXIT" do
			for key_stat, stat in pairs(end_status) do
				rv = (dict.buffer("GET_PRI_ELEMENTS", nil, buff, nil, true ))
				--status is the second byte of return data
				rv = string.unpack("B", rv, 2)
				if rv == dict.op_buffer[stat] then 
					if debug then print("buffer", buff, rv, "matched", stat) end
					rv = "EXIT"
					break
				else
					if debug then print("buffer", buff, "is", rv, "not", stat) end
				end
			end
		end

	end
end

-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
buffers.allocate = allocate
buffers.status_wait = status_wait

-- return the module's table
return buffers

-- old C file:

--
--/* Desc:Payload OUT transfer
-- * Pre: buffers are allocated operation started
-- * Post:payload of length transfered to USB device
-- * Rtn: SUCCESS if no errors
-- */
--int payload_out( USBtransfer *transfer, uint8_t *data, int length ) 
--{
--	check( length < MAX_VUSB+3, "can't transfer more than %d bytes per transfer", MAX_VUSB+2 );
--	//if over 254 bytes, must stuff first two bytes in setup packet
--	if ( length > MAX_VUSB ) {
--		return dictionary_call( transfer,	DICT_BUFFER,	BUFF_OUT_PAYLOAD_2B_INSP,
--			//byte0, 	byte1, 				bytes3-254
--			//data[0], 	data[1],	USB_OUT,	&data[2],	length-2);
--			((data[0]<<8) | data[1]), 	NILL,	USB_OUT,	&data[2],	length-2);
--	} else {
--		return dictionary_call( transfer,	DICT_BUFFER,	BUFF_PAYLOAD,
--			NILL, 		NILL,		USB_OUT,	data,		length);
--	}
--
--error:
--	return ~SUCCESS;
--}
--
