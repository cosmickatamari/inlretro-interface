
-- create the module's table
local dump = {}

-- import required modules
local dict = require "scripts.app.dict"
local buffers = require "scripts.app.buffers"
local snes = require "scripts.app.snes"

-- file constants

-- local functions
local function dumptocallback( callback, sizeKB, map, mem, debug )

	local buff0 = 0
	local buff1 = 1
	local cur_buff_status = 0
	local data = nil --lua stores data in strings

	if debug then print("dumping cart") end

	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )
	--reset buffers first
	dict.buffer("RAW_BUFFER_RESET")

	--need to allocate some buffers for dumping
	--2x 128Byte buffers
	local num_buffers = 2
	local buff_size = 128	
	if debug then print("allocating buffers") end
	assert(buffers.allocate( num_buffers, buff_size ), "fail to allocate buffers")

	--set buffer elements as needed
	--set reload which gets added to page_num after each buffer read
	--set reload to 256 = 1 when translated to page_num (done in allocate buffers funct)
	--set page_num to non-zero if offset arg sent
	--set mem_type and part_num to designate how to get/write data
	if debug then print("setting map n part") end
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer[mem]<<8 | dict.op_buffer["MASKROM"]), buff0 )
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer[mem]<<8 | dict.op_buffer["MASKROM"]), buff1 )
	--set multiple and add_mult only when flashing
	--set mapper, map_var, and function to designate read/write algo
	
	if debug then print("setting map n mapvar") end
	--need to handle raw data, or defines being used for mapper
	--dict.op_buffer[map] will be nil for raw values
	local mapper = dict.op_buffer[map]
	if not mapper then
		mapper = map
	end
	--dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer[map]<<8 | dict.op_buffer["NOVAR"]), buff0 )
	--dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer[map]<<8 | dict.op_buffer["NOVAR"]), buff1 )
	dict.buffer("SET_MAP_N_MAPVAR", (mapper<<8 | dict.op_buffer["NOVAR"]), buff0 )
	dict.buffer("SET_MAP_N_MAPVAR", (mapper<<8 | dict.op_buffer["NOVAR"]), buff1 )

	--tell buffers what function to use for dumping
	--TODO when start implementing other mappers
	
	--debugging print out buffer elements
	--get_operation( transfer );
	--print("\nget operation:")
	--dict.operation("GET_OPERATION" )
	--print("\n\ngetting cur_buff status")
	--dict.buffer("GET_CUR_BUFF_STATUS" )
	--print("\n\ngetting elements")
	--dict.buffer("GET_PRI_ELEMENTS", nil, buff0 )
	--dict.buffer("GET_PRI_ELEMENTS", nil, buff1 )
	--dict.buffer("GET_SEC_ELEMENTS", nil, buff0 )
	--dict.buffer("GET_SEC_ELEMENTS", nil, buff1 )
	--dict.buffer("GET_PAGE_NUM", nil, buff0 )
	--dict.buffer("GET_PAGE_NUM", nil, buff1 )
	
	if debug then print("\n\nsetting operation STARTDUMP") end
	--inform buffer manager to start dumping operation now that buffers are initialized
	dict.operation("SET_OPERATION", dict.op_buffer["STARTDUMP"] )

	--manager updates buffer status' so they'll start dumping
	--once they're full manager prepares them to be read back on USB payloads
	--once the next payload request happens manager knows last buffer can start dumping again
	--buffer updates it's elements and goes off to dump next page
	
	local tstart = os.clock();
	local tlast = tstart

	if debug then print("starting first payload") end
	--now just need to call series of payload IN transfers to retrieve data
	for i=1, (sizeKB*1024/buff_size) do	--dump next buff
		--stm adapter had trouble dumping
		--same buffer was getting sent twice, so I think 
		--buffer mangager wasn't getting enough time to update
		--to point to next buffer and last buffer was redumped
		--that doesn't quite make sense, but something like that is going on
		--need to setup buffer manager to nak anytime something like this happens
		--the following setup slows down everything due to status waits..
--		buffers.status_wait({buff0}, {"DUMPED"}) 
--		callback( dict.buffer_payload_in( buff_size ))
--		buffers.status_wait({buff1}, {"DUMPED"}) 

		--stm adapter having issues with race situation..
		--can't dump as fast as host is requesting
		--and driver doesn't nak until ready to send data
		cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		while (cur_buff_status ~= dict.op_buffer["DUMPED"]) do
		--	nak = nak +1
			--print(nak, "cur_buff->status: ", cur_buff_status)
			cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		end
		callback( dict.buffer_payload_in( buff_size ))
	--	print("dumped page:", i)
		
		--if ( (i % (1024*1024/buff_size/16)) == 0) then
		if ( (i % (4*2024*1024/buff_size/16)) == 0) then
			local tdelta = os.clock() - tlast
			if debug then print("time delta:", tdelta, "seconds, speed:", (1024/16/tdelta), "KBps") end
			--print("dumped part:", i/1024, "of 16 \n") 
			if debug then print("dumped part:", i/(4*1024), "of 4 \n") end
			tlast = os.clock();
		end
	end

	if debug then print("DUMPING DONE") end

	tstop = os.clock()
	timediff = ( tstop-tstart)
	if debug then print("total time:", timediff, "seconds, average speed:", (sizeKB/timediff), "KBps") end

	--buffer manager updates from USB_UNLOADING -> DUMPING -> DUMPED
	--while one buffer is unloading, it sends next buffer off to dump
	--payout opcode updates from DUMPED -> USB_LOADING
	--so end result is buff0 will get sent off to dump extra data that's not needed
	--but we never call payload on it, so buff1 never moves from USB_UNLOADING
	--but it has to be done unloading if we sent a subsequent setup packet
	--buffers.status_wait({buff0, buff1}, {"DUMPED","USB_UNLOADING"}) 
	--in reality I don't think this wait is needed.  Because we've already gotten our data if
	--we're at this point..
	--what we really need to do is set the buffer's status' to a reset state 
	--that way we can give them new instructions before restarting DUMP of CHR portion
	--best way can think of doing this is a operation "RESET" which updates buffer status,
	--without deallocating them.  In reality should be able to do this by setting operation to reset.
	--and having STARTDUMP/FLASH initialize buffer status' as well.
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )
	dict.buffer("RAW_BUFFER_RESET")
end

local function dumptofile( file, sizeKB, map, mem, debug )
	local bytes_written = 0
	dumptocallback(
		function (data)
			file:write(data)
			bytes_written = bytes_written + #data
		end,
		sizeKB, map, mem, debug
	)
	-- print("Total bytes written:", bytes_written)  -- Removed for cleaner ROM dump output
end


--//main collected as much data about cart as possible without reading roms
--//now it's time to start running CRC's to try and finalize mapper/config
--//Once final mapper is known store header data in rom file and start dumping!
local function dump_nes( file, debug )

	local buff0 = 0
	local buff1 = 1
	--local i = nil
	local cur_buff_status = 0
--	uint8_t data[buff_size];
	local data = nil --lua stores data in strings

	if debug then print("dumping cart") end
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
--	//Run some CRC's to determine size of memories
--
--	//setup buffers and manager
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )
--	//reset buffers first
	dict.buffer("RAW_BUFFER_RESET")

--	//need to allocate some buffers for dumping
--	//2x 128Byte buffers
	local num_buffers = 2
	local buff_size = 128	
	print("allocating buffers")
	assert(buffers.allocate( num_buffers, buff_size ), "fail to allocate buffers")

--	//set buffer elements as needed
--	//set reload which gets added to page_num after each buffer read
--	//set reload to 256 = 1 when translated to page_num (done in allocate buffers funct)
--	//set page_num to non-zero if offset arg sent
--	//set mem_type and part_num to designate how to get/write data
--	check(! set_mem_n_part( transfer, buff0, PRGROM, MASKROM ), "Unable to set mem_type and part");
	print("setting map n part")
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["PRGROM"]<<8 | dict.op_buffer["MASKROM"]), buff0 )
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["PRGROM"]<<8 | dict.op_buffer["MASKROM"]), buff1 )
--	//set multiple and add_mult only when flashing
--	//set mapper, map_var, and function to designate read/write algo
--
--	//just dump visible NROM memory to start
	print("setting map n mapvar")
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer["NROM"]<<8 | dict.op_buffer["NOVAR"]), buff0 )
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer["NROM"]<<8 | dict.op_buffer["NOVAR"]), buff1 )
--
--	//tell buffers what function to use for dumping
--	//TODO when start implementing other mappers
--
--	//debugging print out buffer elements
--	//get_operation( transfer );
	--print("\nget operation:")
	--dict.operation("GET_OPERATION" )
	--print("\n\ngetting cur_buff status")
	--dict.buffer("GET_CUR_BUFF_STATUS" )
	--print("\n\ngetting elements")
	--dict.buffer("GET_PRI_ELEMENTS", nil, buff0 )
	--dict.buffer("GET_PRI_ELEMENTS", nil, buff1 )
	--dict.buffer("GET_SEC_ELEMENTS", nil, buff0 )
	--dict.buffer("GET_SEC_ELEMENTS", nil, buff1 )
	--dict.buffer("GET_PAGE_NUM", nil, buff0 )
	--dict.buffer("GET_PAGE_NUM", nil, buff1 )
--
	print("\n\nsetting operation STARTDUMP");
--	//inform buffer manager to start dumping operation now that buffers are initialized
--	check(! set_operation( transfer, STARTDUMP ), "Unable to set buffer operation");
	dict.operation("SET_OPERATION", dict.op_buffer["STARTDUMP"] )
--
	--need these calls to delay things a bit to let first buffer dump complete..
--	dict.operation("GET_OPERATION" )
--	dict.buffer("GET_PRI_ELEMENTS", nil, buff0 )
--	dict.buffer("GET_PRI_ELEMENTS", nil, buff1 )
--	//manager updates buffer status' so they'll start dumping
--	//once they're full manager prepares them to be read back on USB payloads
--	//once the next payload request happens manager knows last buffer can start dumping again
--	//buffer updates it's elements and goes off to dump next page
--
	print("starting first payload");
	--dict.buffer("BUFF_PAYLOAD")
	--file:write("HELLO FILE!")
--	file:write( dict.buffer_payload_in( buff_size ))
--	print("first payload done");
--
--	print("second payload");
--	file:write( dict.buffer_payload_in( buff_size ))
--
--	clock_t tstart, tstop;
--	tstart = clock();
--
	--wait for first buffer to finish dumping before calling payload
	buffers.status_wait({buff0}, {"DUMPED"}) 
--	//now just need to call series of payload IN transfers to retrieve data
	--for i=1, (1024*1024/buff_size) do
	for i=1, (32*1024/buff_size) do

--		//ensure cur_buff is DUMPED prior to requsting data
--		Removed this check as the device USB driver & buffer.c should properly handle this case
--		if the device isn't ready it should ignore the host and make it resend it's request.
--		check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
		--cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		--while (cur_buff_status ~= dict.op_buffer["DUMPED"]) do
--		--while (cur_buff_status != DUMPED ) {
		--	print("cur_buff->status: ", cur_buff_status)
		--	cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
--		--	check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--		--}
		--end
--	//for( i=0; i<(8*KByte/buff_size); i++) {
--		//payload transfer in and append to file
--	//	if ( i % 256 == 0 ) debug("payload in #%d", i);
--		check(! payload_in( transfer, data, buff_size ), "Error with payload IN");
--		if (i==0) printf("first byte: %x\n", data[0]);
--		check(! append_to_file( rom, data, buff_size ), "Error with file append");
		file:write( dict.buffer_payload_in( buff_size ))
	end
--	}
	print("payload done");
	--buffer manager updates from USB_UNLOADING -> DUMPING -> DUMPED
	--while one buffer is unloading, it sends next buffer off to dump
	--payout opcode updates from DUMPED -> USB_LOADING
	--so end result is buff0 will get sent off to dump extra data that's not needed
	--but we never call payload on it, so buff1 never moves from USB_UNLOADING
	--but it has to be done unloading if we sent a subsequent setup packet
	--buffers.status_wait({buff0, buff1}, {"DUMPED","USB_UNLOADING"}) 
	--in reality I don't think this wait is needed.  Because we've already gotten our data if
	--we're at this point..
	--what we really need to do is set the buffer's status' to a reset state 
	--that way we can give them new instructions before restarting DUMP of CHR portion
	--best way can think of doing this is a operation "RESET" which updates buffer status,
	--without deallocating them.  In reality should be able to do this by setting operation to reset.
	--and having STARTDUMP/FLASH initialize buffer status' as well.
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )
	dict.buffer("RAW_BUFFER_RESET")

--	//need to allocate some buffers for dumping
--	//2x 128Byte buffers
	num_buffers = 2
	buff_size = 128	
	print("allocating buffers")
	assert(buffers.allocate( num_buffers, buff_size ), "fail to allocate buffers")

--	//set buffer elements as needed
--	//set reload which gets added to page_num after each buffer read
--	//set reload to 256 = 1 when translated to page_num (done in allocate buffers funct)
--	//set page_num to non-zero if offset arg sent
--	//set mem_type and part_num to designate how to get/write data
--	check(! set_mem_n_part( transfer, buff0, PRGROM, MASKROM ), "Unable to set mem_type and part");
	print("setting map n part")
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["CHRROM"]<<8 | dict.op_buffer["MASKROM"]), buff0 )
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["CHRROM"]<<8 | dict.op_buffer["MASKROM"]), buff1 )
--	//set multiple and add_mult only when flashing
--	//set mapper, map_var, and function to designate read/write algo
--
--	//just dump visible NROM memory to start
	print("setting map n mapvar")
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer["NROM"]<<8 | dict.op_buffer["NOVAR"]), buff0 )
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer["NROM"]<<8 | dict.op_buffer["NOVAR"]), buff1 )
--
--
	print("\n\nsetting operation STARTDUMP");
--	//inform buffer manager to start dumping operation now that buffers are initialized
--	check(! set_operation( transfer, STARTDUMP ), "Unable to set buffer operation");
	dict.operation("SET_OPERATION", dict.op_buffer["STARTDUMP"] )
--
--	tstop = os.clock();
--	float timediff = ( (float)(tstop-tstart) / CLOCKS_PER_SEC);
--	printf("total time: %fsec, speed: %fKBps", timediff, (512/timediff));
--	//TODO flush file from time to time..?
--
--
--	//tell buffer manager when to stop
--	// or not..?  just reset buffers and start next memory or quit
--	//reset buffers and setup to dump CHR-ROM
	--Can't get things to work without resetting all the buffers for some reason..
	--Think the issue is need to get the buffer status needs reset
--	dict.buffer("RAW_BUFFER_RESET")
--	print("reallocate buffers")
--	assert(buffers.allocate( num_buffers, buff_size ), "fail to allocate buffers")
	
	--wait for first buffer to finish dumping prior to calling payload
	buffers.status_wait({buff0}, {"DUMPED"}) 
	
	for i=1, (8*1024/buff_size) do
		--cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		--while (cur_buff_status ~= dict.op_buffer["DUMPED"]) do
--		--while (cur_buff_status != DUMPED ) {
		--	print("cur_buff->status: ", cur_buff_status)
		--	cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
--		--	check(! get_cur_buff_status( transfer, &cur_buff_status ), "Error retrieving cur_buff->status");
--		--}
		--end
		file:write( dict.buffer_payload_in( buff_size ))
	end
	print("payload done");
--
--	//close file in main
--
--	//reset io at end
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )
	dict.buffer("RAW_BUFFER_RESET")
	dict.io("IO_RESET")

	return true
end


local function dump_snes( file, mapping, debug )

	local buff0 = 0
	local buff1 = 1
	local cur_buff_status = 0
	local data = nil --lua stores data in strings

	if mapping ~= "LOROM" then
		print("currently only support LOROM SNES mapping!!!")
	end

	if debug then print("dumping cart") end

	--start with reset and init
	--dict.io("IO_RESET")
	dict.io("SNES_INIT")

	--set cart in play mode
	snes.play_mode()

	--setup buffers and manager
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )
	--reset buffers first
	dict.buffer("RAW_BUFFER_RESET")

	--need to allocate some buffers for dumping
	--2x 128Byte buffers
	local num_buffers = 2
	local buff_size = 128	
	print("allocating buffers")
	assert(buffers.allocate( num_buffers, buff_size ), "fail to allocate buffers")

	--set buffer elements as needed
	--set reload which gets added to page_num after each buffer read
	--set reload to 256 = 1 when translated to page_num (done in allocate buffers funct)
	--set page_num to non-zero if offset arg sent
	--set mem_type and part_num to designate how to get/write data
	print("setting map n part")
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["SNESROM"]<<8 | dict.op_buffer["MASKROM"]), buff0 )
	dict.buffer("SET_MEM_N_PART", (dict.op_buffer["SNESROM"]<<8 | dict.op_buffer["MASKROM"]), buff1 )

	--set multiple and add_mult only when flashing
	--set mapper, map_var, and function to designate read/write algo
	
	print("setting map n mapvar")
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer[mapping]<<8 | dict.op_buffer["NOVAR"]), buff0 )
	dict.buffer("SET_MAP_N_MAPVAR", (dict.op_buffer[mapping]<<8 | dict.op_buffer["NOVAR"]), buff1 )

--	//tell buffers what function to use for dumping
--	//TODO when start implementing other mappers

	print("\n\nsetting operation STARTDUMP");
	--inform buffer manager to start dumping operation now that buffers are initialized
	dict.operation("SET_OPERATION", dict.op_buffer["STARTDUMP"] )

	--need these calls to delay things a bit to let first buffer dump complete..
	--wait for first buffer to finish dumping before calling payload
	--buffers.status_wait({buff0}, {"DUMPED"}) 

	local tstart = os.clock();
	local tlast = tstart

	print("starting first payload");
	--now just need to call series of payload IN transfers to retrieve data
	for i=1, (2048*1024/buff_size) do	--dump next buff
	--for i=1, (1024*1024/buff_size) do	--dump buff0 then buff1
	--for i=1, (32*1024/buff_size) do	--dump buff0 then buff1
		--stm adapter had trouble dumping
		--same buffer was getting sent twice, so I think 
		--buffer mangager wasn't getting enough time to update
		--to point to next buffer and last buffer was redumped
		--that doesn't quite make sense, but something like that is going on
		--need to setup buffer manager to nak anytime something like this happens
		--the following setup slows down everything due to status waits..
--		buffers.status_wait({buff0}, {"DUMPED"}) 
--		file:write( dict.buffer_payload_in( buff_size ))
--		buffers.status_wait({buff1}, {"DUMPED"}) 

		--stm adapter having issues with race situation..
		--can't dump as fast as host is requesting
		--and driver doesn't nak until ready to send data
		cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		while (cur_buff_status ~= dict.op_buffer["DUMPED"]) do
		--	nak = nak +1
			--print(nak, "cur_buff->status: ", cur_buff_status)
			cur_buff_status = dict.buffer("GET_CUR_BUFF_STATUS")
		end
		file:write( dict.buffer_payload_in( buff_size ))
	--	print("dumped page:", i)
		
		--if ( (i % (1024*1024/buff_size/16)) == 0) then
		if ( (i % (4*2024*1024/buff_size/16)) == 0) then
			local tdelta = os.clock() - tlast
			print("time delta:", tdelta, "seconds, speed:", (1024/16/tdelta), "KBps");
			--print("dumped part:", i/1024, "of 16 \n") 
			print("dumped part:", i/(4*1024), "of 4 \n") 
			tlast = os.clock();
		end
	end

	print("DUMPING DONE")

	tstop = os.clock()
	timediff = ( tstop-tstart)
	print("total time:", timediff, "seconds, average speed:", (2048/timediff), "KBps")

	--buffer manager updates from USB_UNLOADING -> DUMPING -> DUMPED
	--while one buffer is unloading, it sends next buffer off to dump
	--payout opcode updates from DUMPED -> USB_LOADING
	--so end result is buff0 will get sent off to dump extra data that's not needed
	--but we never call payload on it, so buff1 never moves from USB_UNLOADING
	--but it has to be done unloading if we sent a subsequent setup packet
	--buffers.status_wait({buff0, buff1}, {"DUMPED","USB_UNLOADING"}) 
	--in reality I don't think this wait is needed.  Because we've already gotten our data if
	--we're at this point..
	--what we really need to do is set the buffer's status' to a reset state 
	--that way we can give them new instructions before restarting DUMP of CHR portion
	--best way can think of doing this is a operation "RESET" which updates buffer status,
	--without deallocating them.  In reality should be able to do this by setting operation to reset.
	--and having STARTDUMP/FLASH initialize buffer status' as well.
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )
	dict.buffer("RAW_BUFFER_RESET")

	--close file in main
	--reset io at end
	dict.operation("SET_OPERATION", dict.op_buffer["RESET"] )
	dict.buffer("RAW_BUFFER_RESET")
--	dict.io("IO_RESET")

	return true
end

-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
dump.dump_nes = dump_nes
dump.dump_snes = dump_snes
dump.dumptofile = dumptofile
dump.dumptocallback = dumptocallback

-- return the module's table
return dump
