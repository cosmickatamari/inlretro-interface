#ifndef _shared_dict_gameboy_h
#define _shared_dict_gameboy_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// GAMEBOY DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/gameboy.c
//
//=============================================================================================
//=============================================================================================


#define	GAMEBOY_RD	0	//RL=3  return error code, data len = 1, 1 byte of data
#define	GAMEBOY_WR	1


#endif
