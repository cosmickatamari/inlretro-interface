#ifndef _shared_dict_swim_h
#define _shared_dict_swim_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// SWIM DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/swim.c
//
//=============================================================================================
//=============================================================================================


//activate swim on device as initiated with dict_io SWIM_INIT
//return SUCCESS if device responds with sync frame
#define SWIM_ACTIVATE	0

//hold swim pin low for 128 clocks to init comms
//return SUCCESS if device responds with sync frame
#define	SWIM_RESET	1

//SWIM commands
#define	SWIM_SRST	2	//reset device	RL=3 (error, len, NAK/ACK)

#define	ROTF		0x11	//read on the fly only one byte RL=4 (usberror, len, swimerror, data)
#define	ROTF_HS		0x12	//RL=4
//#define	ROTF_8B		0x18	//read on the fly RL=8
//#define	ROTF_128B	0x1F	//read on the fly RL=128 (current max due to 254B limit)

//write on the fly only one byte
//operand = address (extended addr always 0)
//miscdata = data to write @ address
#define	WOTF		0x21	//RL=3 (error code, data len, 0-NAK 1-ACK) 
#define	WOTF_HS		0x22	//RL=3
//#define	WOTF_8B		0x28	//write 8Bytes on the fly
//#define	WOTF_128B	0x2F	//write 128Bytes on the fly

#endif
