#ifndef _shared_dict_gba_h
#define _shared_dict_gba_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// GBA (gameboy advance) DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/gba.c
//
//=============================================================================================
//=============================================================================================


//must have latched the address first
//rom will auto increment so can just call this repeatedly to read a sequence of addresses
#define	GBA_RD	0	//RL=4  return error code, data len = 1, 2 bytes of data
//#define	GBA_WR	1

//operand A0-15, miscdata A16-23
//leaves /CE low for subsequent accesses
//leaves A16-23 as output
//leaves AD0-15 as input
#define LATCH_ADDR 2	

//take /CE high to finish above access
//put A16-23 back to input
#define RELEASE_BUS 3


#endif
