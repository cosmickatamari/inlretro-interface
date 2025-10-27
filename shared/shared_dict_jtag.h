#ifndef _shared_dict_jtag_h
#define _shared_dict_jtag_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// JTAG DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/jtag.c
//
//=============================================================================================
//=============================================================================================


//JTAG opcodes
#define		GET_CMD		1	//RL=3
#define		SET_CMD		2	//command is only writable by host, read only by engine

#define		SET_CMD_WAIT	3	//RL=3 returns command status effectively set, perform, and get/return command
					//set command and force device to perform command immediately
					//should only be used for quick commands like state change, not for long scan in/outs
					
#define		GET_STATUS	4	//RL=3	only the engine can write to status, ready only by host

#define		SET_NUMCLK	5	//numclk is only writable by host, read only by engine
					//set to zero if would like 256 clocks to be performed
					//range is 1-255, 0 equates to 256 clocks

#define		SET_2B_DATA	7	//miscdata defines the first byte index 
					//0=first 2 bytes (16bits) of DATA array
					//if undefined, should be 0 (first 2 bytes)
				
#define		GET_8B_DATA	8	//RL=10 max lua int, miscdata gives offset of first byte
#define		GET_32B_DATA	9	//RL=34 


//PBJE Paul's Basic Jtag engine commands & status'
#define		PBJE_STATE_CHG	0x01	//data array holds TMS values to clock values bit packed, TDI undefined
//TMS s bit packed, better for USB data compression (contrary to notes)


//DATA SCAN commands, these end with setting TMS to 1 to exit SHIFT-IR/DR completing the SCAN.
//If need to make multiple smaller scans to make up one big scan, this would be the last scan, "HOLD" scans 
//lower down would be the first to second to last scans
#define		PBJE_TDI_SCAN	0x02	//ignore TDO	256max
#define		PBJE_TDO_SCAN0	0x03	//TDI = 0, TMS=0	256max
#define		PBJE_TDO_SCAN1	0x04	//TDI = 1, TMS=0	256max
//#define		PBJE_HALF_SCAN	0x05	//TDI = first half of data array, TDO = second, TMS=0	128max
#define		PBJE_FULL_SCAN	0x06	//TDI = entire data array, TDO dumped into array stomping TDI, TMS=0	256max

//Clocking commands, mostly used for RUNTEST type instructions when waiting for device to complete operation
#define		PBJE_CLOCK0	0x07	//data not used, clock TMS=0 for NUMCLK	
#define		PBJE_CLOCK1	0x08	//data not used, clock TMS=1 for NUMCLK
#define		PBJE_FREE_CLOCK0	0x09	//data not used, clock TMS=0 indefinely
#define		PBJE_FREE_CLOCK1	0x0A	//data not used, clock TMS=1 indefinely
#define		PBJE_LONG_CLOCK0	0x0B	//data contains 32bit uint for number of clocks, TMS=0, numclk not used
#define		PBJE_LONG_CLOCK1	0x0C	//data contains 32bit uint for number of clocks, TMS=1, numclk not used

//These scans leave JTAG SM in SHIFT state so more bits can be shifted in later on
//this is because the last bit is shifted in when exiting SHIFT-IR/DR
#define		PBJE_TDI_SCAN_HOLD	0x0D	//ignore TDO	256max
#define		PBJE_TDO_SCAN0_HOLD	0x0E	//TDI = 0, TMS=0	256max
#define		PBJE_TDO_SCAN1_HOLD	0x0F	//TDI = 1, TMS=0	256max
#define		PBJE_FULL_SCAN_HOLD	0x10	//TDI = entire data array, TDO dumped into array stomping TDI, TMS=0	256max


//TODO, why don't we get unknown opcode when accidentally sending a command as an opcode..? ie dict.jtag("PBJE_INIT")
//that freezes instead of sending back unknown opcode, because it is known you idiot!...
//Statuses & commands to get to the status
#define		PBJE_INIT	0x80	//STATE ONLY!  DON'T USE AS COMMAND!!l init with io dict, this is the state only
#define		PBJE_PROC	0x81
#define		PBJE_DONE	0x82
#define		PBJE_CMD_RX	0x83
#define		PBJE_UNKN_CMD	0xEE
#define		PBJE_OFF	0xF0	//STATE: mcu isn't running the PBJE
#define		PBJE_SHUTDOWN	0xFF	//COMMAND: tell mcu to shutoff PBJE



#endif
