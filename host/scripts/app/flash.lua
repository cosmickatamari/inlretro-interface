
-- create the module's table
local flash = {}

-- import required modules
local dict = require "scripts.app.dict"
local buffers = require "scripts.app.buffers"
local snes = require "scripts.app.snes"

-- file constants

-- local functions
local function write_file( file, sizeKB, map, mem, debug )

	local buff0 = 0
	local buff1 = 1
	local cur_buff_status = 0
	local data = nil --lua stores data in strings

	if debug then print("flashing cart") end

	--start operation at reset	
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )

	--setup buffers and manager
	--reset buffers first
	dict.buffer("RAW_BUFFER_RESET")
	--need to allocate some buffers for flashing
	--2x 256Byte buffers
	local num_buffers = 2
	local buff_size = 256	
	if debug then print("allocating buffers") end
	assert(buffers.allocate( num_buffers, buff_size ), "fail to allocate buffers")

	--set mem_type and part_num to designate how to get/write data
	if debug then print("setting map n part") end
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer[mem]<<8 | dict.op_buffer["MASKROM"]), buff0 )
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer[mem]<<8 | dict.op_buffer["MASKROM"]), buff1 )
	--set multiple and add_mult only when flashing
	--TODO
	
	--set mapper, map_var, and function to designate read/write algo
	--just dump visible NROM memory to start
	if debug then print("setting map n mapvar") end
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer[map]<<8 | dict.op_buffer["NOVAR"]), buff0 )
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer[map]<<8 | dict.op_buffer["NOVAR"]), buff1 )

	if debug then print("\n\nsetting operation STARTFLASH"); end
	--inform buffer manager to start flashing operation now that buffers are initialized
	dict.operation("SET_OPERATION", dict.op_buffer["STARTFLASH"] )

	local tstart = os.clock();
	local tlast = tstart

	local i = 1
	local nak = 0
	--print("file is:", file)
	for bytes in file:lines(buff_size) do
		--if debug then print("payload out") end
		dict.buffer_payload_out( buff_size, bytes )

		cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		while (cur_buff_status ~= dict.op_buffer["EMPTY"]) do
			nak = nak +1
			--print(nak, "cur_buff->status: ", cur_buff_status)
			cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		end
		--if ( i == 2048*1024/buff_size) then break end 
		--if ( i == 32*1024/buff_size) then break end 
		if ( i == sizeKB*1024/buff_size) then break end 
		i = i + 1
	--	if ( (i % (4*2048*1024/buff_size/16)) == 0) then
	--		local tdelta = os.clock() - tlast
	--		print("time delta:", tdelta, "seconds, speed:", (4*2048/16/tdelta), "KBps");
	--		print("flashed part:", i/(4*512), "of 4 \n")
	--		tlast = os.clock();
	--	end
	end
	if debug then print("FLASHING DONE") end
	if debug then print("number of naks", nak) end
	tstop = os.clock()
	timediff = ( tstop-tstart)
	if debug then print("total time:", timediff, "seconds, average speed:", (sizeKB/timediff), "KBps") end

	-- wait till all buffers are done
	--while flashing buffer manager updates from USB_FULL -> FLASHING -> FLASHED
	--then next time a USB_FULL buffer comes it it updates the last buffer (above) to EMPTY
	--the next payload opcode updates from EMPTY -> USB_LOADING
	--so when complete, buff0 should be EMPTY, and buff1 should be FLASHED
	--just pass the possible status to exit wait, and buffer numbers we're waiting on
	buffers.status_wait({buff0, buff1}, {"EMPTY","FLASHED"}) 

	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )

	dict.buffer("RAW_BUFFER_RESET")
end

--[[
local function flash_nes( file, debug )
--{
--	//make some checks to ensure rom is compatible with cart
--
--	//first do some checks like ensuring proper areas or sectors are blank
--
--	//erase sectors or chip as needed
--
--	//reset, allocate, and initialize device buffers
--
--	//initialize mapper registers as needed for memory being programmed
--
--	//set device operation to STARTFLASH
--
--	//send payload data
--
--	//run checksums to verify successful flash operation
--
	local buff0 = 0
	local buff1 = 1
	local cur_buff_status = 0
	local data = nil --lua stores data in strings

	if debug then print("flashing cart") end
--
--	//TODO provide user arg to force all these checks passed
--	//first check if any provided args differ from what was detected
--	check( (cart->console != UNKNOWN), "cartridge not detected, must provide console if autodetection is off");
--
--	if ( rom->console != UNKNOWN ) {
--		check( rom->console == cart->console, 
--			"request system dump doesn't match detected cartridge");
--	}
--	if ( (cart->mapper != UNKNOWN) && (rom->mapper != UNKNOWN) ) {
--		check( rom->mapper == cart->mapper,	
--			"request mapper dump doesn't match detected mapper");
--	}
--
--	//start with reset and init
	dict.io("IO_RESET")
	dict.io("NES_INIT")
--	
--	//start operation at reset	
--	check(! set_operation( transfer, RESET ), "Unable to set buffer operation");
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )
--
--	//setup buffers and manager
--	//reset buffers first
	dict.buffer("RAW_BUFFER_RESET")
--	//need to allocate some buffers for flashing
--	//2x 256Byte buffers
	local num_buffers = 2
	local buff_size = 256	
	print("allocating buffers")
	assert(buffers.allocate( num_buffers, buff_size ), "fail to allocate buffers")
--
--	//tell buffers what function to use for flashing
--	//load operation elements into buff0 and then copy buff0 to oper_info
--	load_oper_info_elements( transfer, cart );
--	get_oper_info_elements( transfer );
--
--	//setup buffers and manager
--	//reset buffers first
--	check(! reset_buffers( transfer ), "Unable to reset device buffers");
--	//need to allocate some buffers for flashing
--	//2x 256Byte buffers
--	check(! allocate_buffers( transfer, num_buffers, buff_size ), "Unable to allocate buffers");
--
--	//set mem_type and part_num to designate how to get/write data
	print("setting map n part")
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["PRGROM"]<<8 | dict.op_buffer["MASKROM"]), buff0 )
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["PRGROM"]<<8 | dict.op_buffer["MASKROM"]), buff1 )
--	//set multiple and add_mult only when flashing
--	//TODO
--	//set mapper, map_var, and function to designate read/write algo
--
--	//just dump visible NROM memory to start
	print("setting map n mapvar")
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer["NROM"]<<8 | dict.op_buffer["NOVAR"]), buff0 )
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer["NROM"]<<8 | dict.op_buffer["NOVAR"]), buff1 )
--
--	//debugging print out buffer elements
	--print("\nget operation:")
	--dict.operation("GET_OPERATION" )
	--print("\n\ngetting cur_buff status")
	--dict.buffer("GET_CUR_BUFF_STATUS" )
	--print("\n\ngetting elements")
	--print(dict.buffer("GET_PRI_ELEMENTS", nil, buff0 ))
	--print(dict.buffer("GET_PRI_ELEMENTS", nil, buff1 ))
	--print(dict.buffer("GET_SEC_ELEMENTS", nil, buff0 ))
	--print(dict.buffer("GET_SEC_ELEMENTS", nil, buff1 ))
	--print(dict.buffer("GET_PAGE_NUM", nil, buff0 )    )
	--print(dict.buffer("GET_PAGE_NUM", nil, buff1 )    )

	print("\n\nsetting operation STARTFLASH");
--	//inform buffer manager to start dumping operation now that buffers are initialized
	dict.operation("SET_OPERATION", dict.op_buffer["STARTFLASH"] )
	--print("set operation STARTFLASH");

--	clock_t tstart, tstop;
--	tstart = clock();
--
--	//now just need to call series of payload IN transfers to retrieve data
--	
--	for( i=0; i<(32*KByte/buff_size); i++) {
	local i = 1
	local nak = 0
	for bytes in file:lines(buff_size) do
		dict.buffer_payload_out( buff_size, bytes )
		--for i = 1, #bytes do
		--	local b = string.unpack("B", bytes, i)
		--	io.write(string.format("%02X ", b))
		--end
--		io.write(string.rep(" ", blocksize - #bytes))
--		bytes = string.gsub(bytes, "%c", ".")
--		io.write(" ", bytes, "\n")
--		break
--		while (cur_buff_status != EMPTY ) {
--			//debug("cur_buff->status: %x ", cur_buff_status);
--			check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--		}
		cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		while (cur_buff_status ~= dict.op_buffer["EMPTY"]) do
			nak = nak +1
			--print(nak, "cur_buff->status: ", cur_buff_status)
			cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
--			check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--		}
		end
		if ( i == 32*1024/buff_size) then break end 
		i = i + 1
	end
	print("number of naks", nak)
--	
--	//The device doesn't have a good way to respond if the last buffer is flashing
--	//and the current one is full.  We can only send a payload if the current buffer
--	//is empty.
	
	-- wait till all buffers are done
	--while flashing buffer manager updates from USB_FULL -> FLASHING -> FLASHED
	--then next time a USB_FULL buffer comes it it updates the last buffer (above) to EMPTY
	--the next payload opcode updates from EMPTY -> USB_LOADING
	--so when complete, buff0 should be EMPTY, and buff1 should be FLASHED
	--just pass the possible status to exit wait, and buffer numbers we're waiting on
	buffers.status_wait({buff0, buff1}, {"EMPTY","FLASHED"}) 

--	//start operation at reset	
--	check(! set_operation( transfer, RESET ), "Unable to set buffer operation");
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )
--
--	//setup buffers and manager
--	//reset buffers first
	dict.buffer("RAW_BUFFER_RESET")
--	//need to allocate some buffers for flashing
--	//2x 256Byte buffers
	num_buffers = 2
	buff_size = 256	
	print("allocating buffers")
	assert(buffers.allocate( num_buffers, buff_size ), "fail to allocate buffers")
--
--	//tell buffers what function to use for flashing
--	//load operation elements into buff0 and then copy buff0 to oper_info
--	load_oper_info_elements( transfer, cart );
--	get_oper_info_elements( transfer );
--
--	//setup buffers and manager
--	//reset buffers first
--	check(! reset_buffers( transfer ), "Unable to reset device buffers");
--	//need to allocate some buffers for flashing
--	//2x 256Byte buffers
--	check(! allocate_buffers( transfer, num_buffers, buff_size ), "Unable to allocate buffers");
--
--	//set mem_type and part_num to designate how to get/write data
	print("setting map n part")
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["CHRROM"]<<8 | dict.op_buffer["MASKROM"]), buff0 )
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["CHRROM"]<<8 | dict.op_buffer["MASKROM"]), buff1 )
--	//set multiple and add_mult only when flashing
--	//TODO
--	//set mapper, map_var, and function to designate read/write algo
--
--	//just dump visible NROM memory to start
	print("setting map n mapvar")
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer["NROM"]<<8 | dict.op_buffer["NOVAR"]), buff0 )
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer["NROM"]<<8 | dict.op_buffer["NOVAR"]), buff1 )
--
--	//debugging print out buffer elements
	--print("\nget operation:")
	--dict.operation("GET_OPERATION" )
	--print("\n\ngetting cur_buff status")
	--dict.buffer("GET_CUR_BUFF_STATUS" )
	--print("\n\ngetting elements")
	--print(dict.buffer("GET_PRI_ELEMENTS", nil, buff0 ))
	--print(dict.buffer("GET_PRI_ELEMENTS", nil, buff1 ))
	--print(dict.buffer("GET_SEC_ELEMENTS", nil, buff0 ))
	--print(dict.buffer("GET_SEC_ELEMENTS", nil, buff1 ))
	--print(dict.buffer("GET_PAGE_NUM", nil, buff0 )    )
	--print(dict.buffer("GET_PAGE_NUM", nil, buff1 )    )

	print("\n\nsetting operation STARTFLASH");
--	//inform buffer manager to start dumping operation now that buffers are initialized
	dict.operation("SET_OPERATION", dict.op_buffer["STARTFLASH"] )
	print("set operation STARTFLASH");

--	clock_t tstart, tstop;
--	tstart = clock();
--
--	//now just need to call series of payload IN transfers to retrieve data
--	
--	for( i=0; i<(32*KByte/buff_size); i++) {
	local i = 1
	local nak = 0
	for bytes in file:lines(buff_size) do
		dict.buffer_payload_out( buff_size, bytes )
		--for i = 1, #bytes do
		--	local b = string.unpack("B", bytes, i)
		--	io.write(string.format("%02X ", b))
		--end
--		io.write(string.rep(" ", blocksize - #bytes))
--		bytes = string.gsub(bytes, "%c", ".")
--		io.write(" ", bytes, "\n")
--		break
--		while (cur_buff_status != EMPTY ) {
--			//debug("cur_buff->status: %x ", cur_buff_status);
--			check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--		}
		cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		while (cur_buff_status ~= dict.op_buffer["EMPTY"]) do
			nak = nak +1
			--print(nak, "cur_buff->status: ", cur_buff_status)
			cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
--			check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--		}
		end
		if ( i == 8*1024/buff_size) then break end 
		i = i + 1
	end
	print("number of naks", nak)
--	
--	//The device doesn't have a good way to respond if the last buffer is flashing
--	//and the current one is full.  We can only send a payload if the current buffer
--	//is empty.
	
	-- wait till all buffers are done
	--while flashing buffer manager updates from USB_FULL -> FLASHING -> FLASHED
	--then next time a USB_FULL buffer comes it it updates the last buffer (above) to EMPTY
	--the next payload opcode updates from EMPTY -> USB_LOADING
	--so when complete, buff0 should be EMPTY, and buff1 should be FLASHED
	--just pass the possible status to exit wait, and buffer numbers we're waiting on
	buffers.status_wait({buff0, buff1}, {"EMPTY","FLASHED"}) 
--	
--		//Read next chunk from file
--		check(! read_from_file( rom, data, buff_size ), "Error with file read");
--
--		//ensure cur_buff is EMPTY prior to sending data
--		check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--		while (cur_buff_status != EMPTY ) {
--			//debug("cur_buff->status: %x ", cur_buff_status);
--			check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--		}
--
--		//send data
--		check(! payload_out( transfer, data, buff_size ), "Error with payload OUT");
--		//if ( i % 256 == 0 ) debug("payload in #%d", i);
--		if ( i % 32 == 0 ) debug("payload out #%d", i);
--	}
--	check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--	//debug("\n\n\ncur_buff->status: %x\n", cur_buff_status);
--	
--	//add check to ensure both buffers are done and operation is okay
--	//need to get status of buff1 and make sure it's flashed
--	while (cur_buff_status != FLASHED ) {
--		check(! get_buff_element_value( transfer, buff1, GET_PRI_ELEMENTS, BUFF_STATUS, &cur_buff_status ), 
--			"Error retrieving buffer status post flashing");
--	//	debug("\n\n\ncur_buff->status: %x\n", cur_buff_status);
--	}
--
--	debug("payload done");
--
--	//end operation at reset	
--	check(! set_operation( transfer, RESET ), "Unable to set buffer operation");
--
--	tstop = clock();
--	float timediff = ( (float)(tstop-tstart) / CLOCKS_PER_SEC);
--	printf("total time: %fsec, speed: %fKBps\n", timediff, (32/timediff));
--	//TODO flush file from time to time..?
--
--
--	//tell buffer manager when to stop
--	// or not..?  just reset buffers and start next memory or quit
--	//reset buffers and setup to dump CHR-ROM
--	
--	//load operation elements into buff0 and then copy buff0 to oper_info
--	load_oper_info_elements_chr( transfer, cart );
--	get_oper_info_elements( transfer );
--
--	check(! reset_buffers( transfer ), "Unable to reset device buffers");
--	check(! allocate_buffers( transfer, num_buffers, buff_size ), "Unable to allocate buffers");
--	check(! set_mem_n_part( transfer, buff0, CHRROM, SST_MANF_ID ), "Unable to set mem_type and part");
--	check(! set_mem_n_part( transfer, buff1, CHRROM, SST_MANF_ID ), "Unable to set mem_type and part");
--	check(! set_map_n_mapvar( transfer, buff0, NROM, NILL ), "Unable to set mapper and map_var");
--	check(! set_map_n_mapvar( transfer, buff1, NROM, NILL ), "Unable to set mapper and map_var");
--
--	debug("\n\nsetting operation STARTFLASH");
--	//inform buffer manager to start dumping operation now that buffers are initialized
--	check(! set_operation( transfer, STARTFLASH ), "Unable to set buffer operation");
--
--
--	tstart = clock();
--
--	//now just need to call series of payload IN transfers to retrieve data
--	
--	for( i=0; i<(8*KByte/buff_size); i++) {
--	
--		//Read next chunk from file
--		check(! read_from_file( rom, data, buff_size ), "Error with file read");
--
--		//ensure cur_buff is EMPTY prior to sending data
--		check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--		while (cur_buff_status != EMPTY ) {
--			//debug("cur_buff->status: %x ", cur_buff_status);
--			check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--		}
--
--		//send data
--		check(! payload_out( transfer, data, buff_size ), "Error with payload OUT");
--		//if ( i % 256 == 0 ) debug("payload in #%d", i);
--		if ( i % 32 == 0 ) debug("payload out #%d", i);
--	}
--	check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--	//debug("\n\n\ncur_buff->status: %x\n", cur_buff_status);
--	
--	//check to ensure both buffers are done and operation is okay before resetting
--	//need to get status of buff1 and make sure it's flashed
--	while (cur_buff_status != FLASHED ) {
--		check(! get_buff_element_value( transfer, buff1, GET_PRI_ELEMENTS, BUFF_STATUS, &cur_buff_status ), 
--			"Error retrieving buffer status post flashing");
--	//	debug("\n\n\ncur_buff->status: %x\n", cur_buff_status);
--	}
--
--	debug("payload done");
--	//close file in main
--	
--	//end operation at reset	
--	check(! set_operation( transfer, RESET ), "Unable to set buffer operation");
--
--	//reset io at end
--	io_reset( transfer );
--
--	return SUCCESS;
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )
	dict.buffer("RAW_BUFFER_RESET")
	dict.io("IO_RESET")

end
--]]


local function flash_snes( file, debug )
--	//make some checks to ensure rom is compatible with cart
--
--	//first do some checks like ensuring proper areas or sectors are blank
--
--	//erase sectors or chip as needed
--
--	//reset, allocate, and initialize device buffers
--
--	//initialize mapper registers as needed for memory being programmed
--
--	//set device operation to STARTFLASH
--
--	//send payload data
--
--	//run checksums to verify successful flash operation
--
	local buff0 = 0
	local buff1 = 1
	local cur_buff_status = 0
	local data = nil --lua stores data in strings

	if debug then print("flashing cart") end

--	//start with reset and init
--	dict.io("IO_RESET")
	dict.io("SNES_INIT")

--	//start operation at reset	
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )

--	//setup buffers and manager
--	//reset buffers first
	dict.buffer("RAW_BUFFER_RESET")
--	//need to allocate some buffers for flashing
--	//2x 256Byte buffers
	local num_buffers = 2
	local buff_size = 256	
	print("allocating buffers")
	assert(buffers.allocate( num_buffers, buff_size ), "fail to allocate buffers")

--	//set mem_type and part_num to designate how to get/write data
	print("setting map n part")
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["SNESROM"]<<8 | dict.op_buffer["MASKROM"]), buff0 )
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["SNESROM"]<<8 | dict.op_buffer["MASKROM"]), buff1 )
--	//set multiple and add_mult only when flashing
--	//TODO
--	//set mapper, map_var, and function to designate read/write algo
--
--	//just dump visible NROM memory to start
	print("setting map n mapvar")
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer["LOROM"]<<8 | dict.op_buffer["NOVAR"]), buff0 )
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer["LOROM"]<<8 | dict.op_buffer["NOVAR"]), buff1 )

	--set cart in program mode
	snes.prgm_mode()

	print("\n\nsetting operation STARTFLASH");
--	//inform buffer manager to start dumping operation now that buffers are initialized
	dict.operation("SET_OPERATION", dict.op_buffer["STARTFLASH"] )
	print("set operation STARTFLASH");	--this prints fine not getting stuck above here

	cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
	print("got status")
	dict.operation("GET_OPERATION")
	print("got operation")
	
	--think the not responding bug is related to payload out before device is ready..?

	local tstart = os.clock();
	local tlast = tstart

	local i = 1
	local nak = 0
	for bytes in file:lines(buff_size) do
		dict.buffer_payload_out( buff_size, bytes )

		cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		while (cur_buff_status ~= dict.op_buffer["EMPTY"]) do
			nak = nak +1
			--print(nak, "cur_buff->status: ", cur_buff_status)
			cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		end
		--if ( i == 2048*1024/buff_size) then break end 
		if ( i == 4096*1024/buff_size) then break end 
--		if ( i == 32*1024/buff_size) then break end 
		i = i + 1
--		if ( (i % (2048*1024/buff_size/16)) == 0) then
--			local tdelta = os.clock() - tlast
--			print("time delta:", tdelta, "seconds, speed:", (2048/16/tdelta), "KBps");
--			print("flashed part:", i/512, "of 16 \n") 
--			tlast = os.clock();
		if ( (i % (4*2048*1024/buff_size/16)) == 0) then
			local tdelta = os.clock() - tlast
			print("time delta:", tdelta, "seconds, speed:", (4*2048/16/tdelta), "KBps");
			print("flashed part:", i/(4*512), "of 4 \n")
			tlast = os.clock();
		end
	end
	print("FLASHING DONE")
	print("number of naks", nak)
	tstop = os.clock()
	timediff = ( tstop-tstart)
	print("total time:", timediff, "seconds, average speed:", (2048/timediff), "KBps")
--	//TODO flush file from time to time..?
--	
--	//The device doesn't have a good way to respond if the last buffer is flashing
--	//and the current one is full.  We can only send a payload if the current buffer
--	//is empty.
	
	-- wait till all buffers are done
	--while flashing buffer manager updates from USB_FULL -> FLASHING -> FLASHED
	--then next time a USB_FULL buffer comes it it updates the last buffer (above) to EMPTY
	--the next payload opcode updates from EMPTY -> USB_LOADING
	--so when complete, buff0 should be EMPTY, and buff1 should be FLASHED
	--just pass the possible status to exit wait, and buffer numbers we're waiting on
	buffers.status_wait({buff0, buff1}, {"EMPTY","FLASHED"}) 

	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )

	--set cart in play mode
	snes.play_mode()

	dict.buffer("RAW_BUFFER_RESET")
--	dict.io("IO_RESET")

end

-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
flash.flash_nes = flash_nes
flash.flash_snes = flash_snes
flash.write_file = write_file

-- return the module's table
return flash
