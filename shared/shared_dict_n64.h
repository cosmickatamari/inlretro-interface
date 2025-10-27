#ifndef _shared_dict_n64_h
#define _shared_dict_n64_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// N64 DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/n64.c
//
//=============================================================================================
//=============================================================================================


#define	N64_RD	0	//RL=4  return error code, data len = 1, 2 bytes of data (D0-15)
// TODO #define	N64_WR	1

#define N64_SET_BANK	2	//operand = A16-31 for next address latch, this merely updates a firmware variable
#define N64_LATCH_ADDR	3	//operand = A0-15 (A0 ignored by rom), BANK from above used for A16-31
#define N64_RELEASE_BUS	4	//take ALE_L/H high to end the access

#endif
