#ifndef _shared_dict_buffer_h
#define _shared_dict_buffer_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// BUFFER DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/buffer.c
//
//=============================================================================================
//=============================================================================================


//raw buffer banks & size
//This determines the raw buffer sram space on avr at firmware compile time
//one byte per bank is instantiated to keep track of that banks' allocation status
//a buffer must be as large as one bank, but a buffer can consume multiple banks
//only limit to buffer size is the buffer structure
//current buffer structure utilizes a single byte for current byte counter
//which limits to 256 bytes per buffer currently
//having 16bit value support would expand this, or somehow shifting current byte
//to account for multiple bytes could expand further
//#define NUM_RAW_BANKS   8	// 8*32 = 256 bytes of buffer
#define NUM_RAW_BANKS   16	//16*32 = 512 bytes of buffer
//#define NUM_RAW_BANKS   24	//24*32 = 768 DAMN THE TORPEDOS FULL SPEED AHEAD!!!

#define RAW_BANK_SIZE   32      //bank size in bytes

//number of buffer objects
//This controls number of static buffer objects instantiated in firmware at compile time
//note this also controls opcodes created/supported by firmware
//reducing number of buffers frees firmware sram by ~16bytes per buffer object
//not much reason to have less than 2 atleast allow double buffering
//so one can be getting loaded/unloaded by USB while other is dumping/flashing
//current max is 8, but only really limited by opcode definitions to address all buffers
//makes #ifdef code simpler to only allow buffer numbers that are power of 2
//#define NUM_BUFFERS_2	2
#define NUM_BUFFERS_4	4
//#define NUM_BUFFERS_8	8


//=============================================================================================
//	OPCODES with up to 24bit operand and optional return value  besides SUCCESS/ERROR_CODE
//	PAYLOAD options listed as well
//=============================================================================================
//	Detect this opcode/operand setup with opcode between the following defines:
//
//------------------------------------
#define BUFF_OPCODE_NRV_MIN	0x00
//opcodes in this range have NO RETURN besides error code and DON'T contain buff# in miscdata byte
//			----------------------------
#define					 BUFFN_INMISC_MIN	0x30	//NOTE OVERLAP!!
//opcodes in this range have NO RETURN besides error code and DO contain buff# in miscdata byte
#define BUFF_OPCODE_NRV_MAX	0x3F
//------------------------------------
#define BUFF_PAYLOADN_MIN	0x40
//opcodes in this range are PAYLOADS and DO contain buff# in miscdata byte
#define BUFF_PAYLOADN_MAX	0x4F
//------------------------------------
#define BUFF_OPCODE_RV_MIN	0x50
//opcodes in this range HAVE RETURN besides error code and DO contain buff# in miscdata byte
#define 				BUFFN_INMISC_MAX	0x5F	//NOTE OVERLAP!!
//			----------------------------
//opcodes in this range HAVE RETURN value plus error code and DON'T contain buff# in miscdata byte
#define BUFF_OPCODE_RV_MAX	0x6F
//------------------------------------
#define BUFF_PAYLOAD_MIN	0x70
//opcodes in this range are PAYLOADS and DO NOT contain buff# in miscdata byte
#define BUFF_PAYLOAD_MAX	0x7F
//=============================================================================================
//=============================================================================================


//------------------------------------------------------------------------------------------------
//opcodes in this range have NO RETURN besides error code and DON'T contain buff# in miscdata byte
//#define BUFF_OPCODE_NRV_MIN	0x00-2F
//------------------------------------------------------------------------------------------------

//blindly clear all allocation of raw buffer space
//reset all buffers to unallocated
//no operands no return value
#define	RAW_BUFFER_RESET	0x00


//------------------------------------------------------------------------------------------------
//opcodes in this range have NO RETURN besides error code and DO contain buff# in miscdata byte
//#define BUFFN_INMISC_MIN	0x30-3F	//NOTE OVERLAP!!
//------------------------------------------------------------------------------------------------
//SET BUFFER ELEMENTS

//memory type and part number
//miscdata: buffer number
//operMSB: memory type
//operLSB: part number
#define SET_MEM_N_PART		0x30
	//operand MSB memtype
	#define PRGROM		0x10
	#define CHRROM		0x11
	#define PRGRAM		0x12
	#define SNESROM		0x13
	#define SNESRAM		0x14
	#define GENESISROM	0x15

	//Read specific sections of memory map
	// 4KB/1KB naming designates the granularity of the starting address
	// Any amount can be read, but unexpected behavior will result when reading past memory map limits
	// designate the address base with mapper since this read is mapper independent
	#define NESCPU_4KB	0x20 	//mapper (bits 3-0) specifies A12-15 (4bits)
	#define NESPPU_1KB	0x21	//mapper (bits 5-2) specifies A10-13 (4bits)
	//DON'T WANT TO USE THESE ANY MORE, USE THE PAGE VERSIONS BELOW

	//since the types above only specify the granularity of the read, there is no reason
	//to limit it to 1-4KByte.  May as well give page granularity and use the whole mapper byte!
	#define NESCPU_PAGE	0x22	//mapper byte specifies A15-8
	#define NESPPU_PAGE	0x23	//mapper byte specifies A13-8	 bits 6 & 7 can't be set
	#define SNESROM_PAGE	0x24	//mapper byte specifies A15-8 ROMSEL low
	#define SNESSYS_PAGE	0x25	//mapper byte specifies A15-8 ROMSEL high
	#define GAMEBOY_PAGE	0x26	//mapper byte specifies A15-8
	#define GBA_ROM_PAGE	0x27	//address must have already been latched with gba dictionary
	#define GENESIS_ROM_PAGE0 0x28	//bank address A17-23 must have been latched already
		//TODO come up with better way to handle genesis address complications
	#define GENESIS_ROM_PAGE1 0x29	//bank address A17-23 must have been latched already
	#define N64_ROM_PAGE	0x30


	#define NESPPU_1KB_TOGGLE 0x31	//similar to PPU page read but /RD signal toggles with each read
	#define NESCPU_4KB_TOGGLE 0x32	//similar to CPU page read but M2 toggles with each read
	#define GENESIS_RAM_PAGE  0x33	//bank address A17-23 must have been latched already

	//operand LSB
	//SST 39SF0x0 manf/prod IDs
	#define SST_MANF_ID	0xBF
	#define SST_PROD_128	0xB5
	#define SST_PROD_256	0xB6
	#define SST_PROD_512	0xB7
	//SRAM manf/prod ID
	#define SRAM		0xAA
	//MASK ROM read only
	#define MASKROM		0xDD

//set multiple and add multiple
//miscdata: buffer number
//operMSB: multiple
//operLSB: add multiple
#define SET_MULT_N_ADDMULT	0x31

//set mapper and mapper variant
//miscdata: buffer number
//operMSB: mapper
//operLSB: mapper variant
#define SET_MAP_N_MAPVAR	0x32
	//operand MSB mapper
	#define NROM	0
	#define MMC1	1
	#define UxROM	2
	#define CNROM	3
	#define MMC3	4
	#define MMC5	5
	#define AxROM	7
	#define MMC2	9
	#define MMC4	10
	#define CDREAM	11
	#define CNINJA	12	//not actually mapper 12, just a temp mapper assignment
	#define A53	28
	#define MAP30 	30
	#define EZNSF	31
	#define BxROM	34
	#define RAMBO	64
	#define H3001	65	//IREM mapper
	#define GxROM	66
	#define SUN3	67
	#define SUN4	68
	#define FME7	69	//SUNSOFT-5 with synth
	#define HDIVER	78
	#define GTROM	111
	#define DxROM	205
	#define NAMCOT3415	206	//NAMCOT-3415 mapper

	#define MM2	253
	#define DPROM	254	//just a random mapper number for whatever I need it for
	#define MMC3S	252
	//	UNKNOWN 255	don't assign to something meaningful
	//operand LSB mapper variant
	#define NOVAR	0


	#define LOROM	0
	#define HIROM	1	//file starts at bank 40 and is mirrored to C0
	#define EXHIROM	2	//file starts at bank C0
	#define SOROM	3	//12MB star ocean mapping

	#define	LOROM_5VOLT	4	//Catskull 5v SNES board with SST PLCC flash
	#define	HIROM_5VOLT	5

	#define	LOROM_3VOLT	6
	#define	HIROM_3VOLT	7

	#define	LOROM_3V_PAGE	8
	#define	HIROM_3V_PAGE	9

	#define	LOROM_3V_VERIFY	10	//same as 3VOLT above, but verifies each byte while writing
	#define	HIROM_3V_VERIFY	11


//set function
//miscdata: buffer number
//operMSB: (might be needed if this is a ponter..?)  or might need more than one function def..
//operLSB: function
#define SET_FUNCTION		0x33


//#define BUFF_OPCODE_NRV_MAX	0x3F
//------------------------------------------------------------------------------------------------
//opcodes in this range are PAYLOADS and DO contain buff# in miscdata byte
//#define BUFF_PAYLOADN_MIN	0x40-4F
//------------------------------------------------------------------------------------------------

//designate what buffer to fill with miscdata byte
//no return value as it's write OUT only
//operandMSB:LSB actually contains first 2 bytes
#define BUFF_OUT_PAYLOADN_2B_INSP	0x40

//designate what buffer to fill/read with miscdata byte
#define BUFF_PAYLOADN			0x41


//#define BUFF_PAYLOADN_MAX	0x4F
//------------------------------------------------------------------------------------------------
//opcodes in this range HAVE RETURN besides error code and DO contain buff# in miscdata byte
//#define BUFF_OPCODE_RV_MIN	0x50-5F
//------------------------------------------------------------------------------------------------

//return buffer elements
//misc/data: buffer number
#define GET_PRI_ELEMENTS	0x50	//RL=8
//rv0: success/error code
//rv1: rdatalen = 6
//rv2: last_idx
#define BUFF_LASTIDX	1
//rv3: status
#define BUFF_STATUS	2
//rv4: cur_byte
#define BUFF_CURBYTE	3
//rv5: reload
#define BUFF_RELOAD	4
//rv6: id
#define BUFF_ID		5
//rv7: function
#define BUFF_FUNC	6


//return buffer elements
//misc/data: buffer number
#define GET_SEC_ELEMENTS	0x51	//RL=8
//rv0: success/error code
//rv1: rdatalen = 6
//rv2: mem_type
#define BUFF_MEMTYPE	1
//rv3: part_num
#define BUFF_PARTNUM	2
//rv4: multiple
#define BUFF_MUL	3
//rv5: add_multiple
#define BUFF_ADDMUL	4
//rv6: mapper
#define BUFF_MAPPER	5
//rv7: mapvar
#define BUFF_MAPVAR	6

//return buffer elements
//misc/data: buffer number
#define GET_PAGE_NUM		0x52	//RL=4
//rv0: success/error code
//rv1: rdatalen = 2
//rv3-2: 16bit page number


//#define BUFFN_INMISC_MAX	0x5F	//NOTE OVERLAP!!
//------------------------------------------------------------------------------------------------
//opcodes in this range HAVE RETURN value plus error code and DON'T contain buff# in miscdata byte
//				0x60-6F
//------------------------------------------------------------------------------------------------

//send bank number and read back it's status
//0xFF-UNALLOC
//gets assigned buffer ID number when allocated
//operandMSB/miscdata: unused
//operandLSB: raw bank number to retrieve status of
//return value status of that raw bank (set to bank id if allocated)
#define GET_RAW_BANK_STATUS	0x60	//RL=3
	//buffer/operation status values
	#define EMPTY 		0x00
	#define RESET		0x01
	#define PROBLEM		0x10
	#define PREPARING	0x20
	#define USB_UNLOADING	0x80
	#define USB_LOADING	0x90
	#define USB_FULL	0x98
	#define CHECKING	0xC0
	#define DUMPING		0xD0
	#define STARTDUMP	0xD2
	#define DUMPED		0xD8
	#define ERASING		0xE0
	#define FLASHING	0xF0
	#define STARTFLASH	0xF2
	#define FLASHED		0xF4
	#define FLASH_WAIT	0xF8
	#define STOPPED		0xFE
	#define UNALLOC 	0xFF

//retrieve cur_buff status
#define GET_CUR_BUFF_STATUS	0x61	//RL=3



//#define BUFF_OPCODE_RV_MAX	0x6F
//------------------------------------------------------------------------------------------------
//opcodes in this range are PAYLOADS and DO NOT contain buff# in miscdata byte
//#define BUFF_PAYLOAD_MIN	0x70-7F
//------------------------------------------------------------------------------------------------


//does NOT designate what buffer to fill with opcode
//endpoint direction determines if read/write
//no operands no return value aside from payload for transfer IN
//max size for these transfers is 254Bytes for IN and OUT
#define BUFF_PAYLOAD				0x70

//does NOT designate what buffer to fill with opcode
//no return value as it's write OUT only
//operandMSB:LSB actually contains first 2 bytes
#define BUFF_OUT_PAYLOAD_2B_INSP		0x71


//#define BUFF_PAYLOAD_MAX	0x7F



//=============================================================================================
//	OPCODES with up to 24bit operand and no return value besides SUCCESS/ERROR_CODE
//	BUFFER NUMBER denoted in lower nibble of opcode
//=============================================================================================
//	Detect this opcode group which uses 3 LSbits to determine which buffer to call
#define BUFF_OPCODE_BUFN_MIN	0x80
#define BUFF_OPCODE_BUFN_MAX	0xFF
//
//
//	Detect this opcode/operand setup with opcode between the following defines:
#define BUFF_OPCODE_BUFN_NRV_MIN	0x80
#define BUFF_OPCODE_BUFN_NRV_MAX	0xBF
//
#define BUFF_OPCODE_BUFN_RV_MIN		0xC0
#define BUFF_OPCODE_BUFN_RV_MAX		0xEF
//
#define BUFF_OPCODE_PAYLOAD_MIN		0xF0
#define BUFF_OPCODE_PAYLOAD_MAX		0xFF
//=============================================================================================
//=============================================================================================


//allocate firmware sram to a buffer
//send a buffer number
//buffer size
//base address 0-255 (in 32byte chunks)
//returns SUCCESS if able to allocate
//returns error code if unable to allocate
//operMSB: id to give to new buffer 
//	(upper id bits used to set any address bits not covered by page and buff size if needed)
//operLSB: base bank number
//misc/data: size (number of banks to allocate to buffer)
//	-size doesn't get stored in buffer, the last_idx does
#define	ALLOCATE_BUFFER0	0x80
#define	ALLOCATE_BUFFER1	0x81
#define	ALLOCATE_BUFFER2	0x82
#define	ALLOCATE_BUFFER3	0x83
#define	ALLOCATE_BUFFER4	0x84
#define	ALLOCATE_BUFFER5	0x85
#define	ALLOCATE_BUFFER6	0x86
#define	ALLOCATE_BUFFER7	0x87


//SET BUFFER ELEMENTS

//set reload and page_num
//misc/data reload
//operMSB:LSB page_num (16 bit)
#define SET_RELOAD_PAGENUM0	0x90
#define SET_RELOAD_PAGENUM1	0x91
#define SET_RELOAD_PAGENUM2	0x92
#define SET_RELOAD_PAGENUM3	0x93
#define SET_RELOAD_PAGENUM4	0x94
#define SET_RELOAD_PAGENUM5	0x95
#define SET_RELOAD_PAGENUM6	0x96
#define SET_RELOAD_PAGENUM7	0x97


//designate what buffer to fill with opcode
//endpoint direction determines if read/write
//no operands no return value aside from payload for transfer IN
//DOES NOT STUFF extra bytes in setup packet for write/OUT transfers
#define BUFF_PAYLOAD0		0xF0
#define BUFF_PAYLOAD1		0xF1
#define BUFF_PAYLOAD2		0xF2
#define BUFF_PAYLOAD3		0xF3
#define BUFF_PAYLOAD4		0xF4
#define BUFF_PAYLOAD5		0xF5
#define BUFF_PAYLOAD6		0xF6
#define BUFF_PAYLOAD7		0xF7



//~16 bytes per buffer...
//as initially defined in firmware
//typedef struct buffer{
//	uint8_t 	*data;		//pointer to base buffer's allocated sram
//      uint8_t         last_idx;       //index of last byte in buffer used to determine when at end of buffer
//	uint8_t		status;		//current status of buffer USB load/unload, flashing, waiting, erase
//	uint8_t 	cur_byte;	//byte currently being loaded/unloaded/flashed/read
//	uint8_t		reload;		//add this number to page_num for next loading
//	uint8_t 	id;		//address bits between buffer size and page number
//					//ie need 2x128 byte buffers making buff_num = A7
//					//ie need 4x64 byte buffers making buff_num = A7:6
//					//ie need 8x32 byte buffers making buff_num = A7:5
//					//CANNOT BE 0xFF "UNALLOC"
//	uint16_t 	page_num;	//address bits beyond buffer's size and buff_num A23-A8
//					//MSB A23-16, LSB A15-8
//	uint8_t		mem_type;	//SNES ROM, SNES RAM, PRG ROM, PRG RAM, CHR ROM, CHR RAM, CPLD, SPI
//	uint8_t		part_num;	//used to define unlock commands, sector erase, etc
//	uint8_t		multiple;	//number of times to program this page
//	uint8_t		add_mult;	//add this number to page_num for multiple programs
//					//CHR shift LSb to A13 (max 2MByte)
//					//PRG shift LSb to A14 (max 4MByte)
//					//SNES add to MSB of page_num (max 16MByte)
//	uint8_t		mapper;		//mapper number of board
//	uint8_t		mapvar;		//mapper variant 
//	uint8_t		function;	//function "pointer" for flash/dump operation control
//}buffer;

//buffer struct
//designed to have multiple buffers instantiated at a time
//buffers are effectively objects who get instructed by host
//commands include things like reading from cartridge rom/ram
//getting filled by usb writes, programming 'themselves' to
//where they belong on the cartridge.  They know how to get
//on/off the cart and have a current status that the host can
//query.  Host then decides when to refill/dump data from
//buffer over usb.  Host also can query buffer to get error
//codes back and and attempt to resolve issues.  Buffers can
//also be instructed to verify themselves with a checksum
//They can verify themselves against cart rom/ram as well.

//atmega164 has 1KByte of SRAM
//VUSB has max of 254 + wValue/wIndex = max 256 bytes without long transfers
//Expecting two 128 byte buffers will be faster than a single 256byte buffer
//That way one buffer could be flashing onto the cart while the other is 
//getting filled 8bytes at a time from USB.  this would proide some double
//buffering speed ups, but not sure how fast that'll be.  Having buffers
//as small as 32bytes might be faster for 4-8MB flash memories as they
//have ability to flash 32Bytes at once.  Could perhaps fill multiple
//32B buffers with one larger 128/256B transfer.  Increasing transfer size
//does speed up overall due to fewer setup and status USB packets.

//USB control transfer:
//	SETUP/DATA STAGES:
//	Token packet- sync, pid, addr, enp, crc5, eop = 35bits
//	Data/setup packet
//	sync, pid, crc16, eop = 67bits
//	setup/payload packet data = 64bits
//	handsk (sync, pid, eop) = 19bit
//	total = 185bits with 64bit payload = 34.6% data utilization per data packet
//	STATUS STAGE:
//	same as above, but zero lenght data packet.
//	total 121bits

//	8byte total payload
//	185 setup + 185 data + 121 status = 491 bits transferred for 64bit payload = 13.03% bus utilization

//	32byte total payload
//	185 setup + 4*185 data + 121 status = 1046 bits xfrd for 4*64=256 payld = 24.47% bus util

//	64byte total payload
//	185 setup + 8*185 data + 121 status = 1786 bits xfrd for 8*64=512 payld = 28.67% bus util

//	128byte total payload
//	185 setup + 16*185 data + 121 status = 3266 bits xfrd for 16*64=1024 payld = 31.35% bus util

//	254byte total payload
//	185 setup + 32*185-16 data + 121 status = 6210 bits xfrd for 31.8*64=2032 payld = 32.72% bus util
//	4.4% speedup than 128

//	256bytes in 254byte xfr 
//	185 setup + 32*185-16 data + 121 status = 6210 bits xfrd for 32*64=2048 payld = 32.98% bus util
//	0.79% speedup than 254 in 254

//	256byte total payload
//	185 setup + 32*185 data + 121 status = 6226 bits xfrd for 32*64=2048 payld = 32.89% bus util

//	512byte total payload
//	185 setup + 64*185 data + 121 status = 12146 bits xfrd for 64*64=4096 payld = 33.72% bus util
//	1% greater bus util compared to 254byte xfr
//	2.2% speedup compared to 256 in 254

//	USB 1.1 Low speed 1.5Mbps
//	maximum theoretical bus utiliation with transfers styles above 
//	1.5Mbps * 33% utilization = 495Kbps = 61.8KBps
//	Will never get to this maximum, as this assumes that bus is in use 100% of the time with no
//	delays waiting for responses etc.  But gives sense of scale for what's possible

//	Probably decent overall speedup by eliminating multiple status packets.  Not sure how many
//	NAK's the old firmware was sending while the device programmed the entire 256byte buffer.
//	but one NAK is more than should be necessary.
//
//	Plan is to support max of 254 byte transfers with 2 bytes stuffed in setup packet
//	Want to compare to 512B long transfers for speed comparison
//	
//	Either way, I can setup the buffers in smaller sizes than the transfers.  Then a buffer could
//	start programming mid usb transfer once it's full.  Want to make effor to hide flash programming
//	wait time behind usb transfer time.

//	some speed testing with 16bit return length variable:
//	128Byte OUT (write) transfers with long transfers DISABLED: 20.04sec/512KByte = 25.55KBps
//	128Byte OUT (write) transfers with long transfers ENABLED:  20.7 sec/512KByte = 24.7 KBps
//	256Byte OUT (write) transfers with long transfers ENABLED:  18.56sec/512KByte = 27.6 KBps
//	254Byte OUT (write) transfers with long transfers DISABLED: 17.9 sec/512KByte = 28.6 KBps (assuming 2 bytes stuffed in setup packet)
//	128Byte  IN (read)  with long xfr DISABLED, w/o usbFuncRd:  30.5 sec/512KByte = 16.8 KBps
//with read data dumping operations and file writing: 128Byte IN    32.25sec/512KByte = 15.8 KBps only 1KBps lost due to dumping operation
//	128Byte  IN (read)  with long xfr DISABLED,   w/usbFuncRd:  34.9 sec/512KByte = 14.7 KBps
//	1033*254Byte  IN (read)  long xfr DISABLED, w/o usbFuncRd:  28.35sec/512KByte = 18.1 KBps
//
//	after concluding that would not be using long transfers, the return length variable
//	was reduced to 8bits (single byte unsigned int) and slight improvement was found:
//	254Byte OUT (write) transfers with long transfers DISABLED: 17.5 sec/512KByte = 29.2 KBps (assuming 2 bytes stuffed in setup packet)
//
//	adding a few checks to usbFunctionWrite to ensure buffer is proper status and not won't be overflowed 
//	presented small reduction in speed:
//	254Byte OUT (write) transfers with long transfers DISABLED: 18.1 sec/512KByte = 28.4 KBps (assuming 2 bytes stuffed in setup packet)
//
//	These tests did nothing with payload once it arrived, so these are practical maximums of V-usb.
//	Conclusion: 
//		-enabling long transfers slows writes (and probably reads)
//		-reads are much slower than writes.
//			found a vusb forum thread quoting 22KBps reads at transfer size of 200bytes
//			he was using atmega16 with 12Mhz clock, so doesn't look like we can 
//			replicate this even with our 'better' conditions.  But our
//			writes are exceeding his 24KBps transfer speeds so we'll take it..
//			https://forums.obdev.at/viewtopic.php?t=3059
//		-enabling usbFunctionRead is slower compared to using usbFunctionSetup alone.
//		-using 254B xfrs with 2 bytes stuffed in setup packet gives decent boost for writes.
//			this is primarily due to speed up of not having long transfers enabled.
//		-not actually certain enabling long transfers will slow down reads, but it certainly does for writes.
//		-reads can't stuff 2 bytes in setup packet because data is going opposite direction as setup packet.
//		-reads do have decent speed boost of ~1.3KBps using 254B * 1033xfrs over 128*2048xfrs
//			for reads to get this speed boost the missing 2 bytes would have to be accumulated in
//			separate buffer and sent separately once full.
//			Only other way without complicating dump algo would be to implement usbFuncRd
//			but that would slow things down and negate the speed boost..
//
//	Speed testing with old firmware and app:
//	fairly certain these were long transfers of 256 bytes each
//	512KB write 30.2sec = 16.7KBps
//	512KB read  34.2sec = 15.0KBps
//
//	Haven't tested for comparison's sake, but original anago/unagi firmware/app was even slower I believe
//	Found quote of Memblers finding ~19sec for 128KB PRG-ROM = 6.7KBps for reads...
//	So shouldn't be hard to beat those speeds
//
//	Checking SST 39SF040 datasheet, the byte program time is max 20usec * 256B page = 5.12usec per page
//	We have some additional CPU execution time overhead above that 5.12usec per page
//	but that shouldn't be significant in comparison, still lots of margin to meet 50usec usbPoll requirement
//	if slow down is noticed during flashing/dumping may be helpful to call usbPoll mid page so
//	the next data packet doesn't have to wait for the last page to complete before it can be accepted/sent
//	to/from the driver.
//
//	Sector erases are maximum of 25usec however which should probably be avoided or used with caution
//	between usbPoll.  However exiting back to main and continuing to poll USB and erasure should be fine
//	as erasing doesn't have to be monitored.  
//
//	Chip erasure is max of 100usec which will most certainly violate 50usec usbPoll req't so make sure 
//	we don't sit and spin waiting for chip to erase without calling usbPoll...
//
//	SNES 4-8MB chip erasure is on the order of 30sec so certainly need to be considerate of flash timing
//	depending on the chip in use.  Avoiding SNES chip erasure when possible presents large chance for 
//	speedup!
//


#endif
