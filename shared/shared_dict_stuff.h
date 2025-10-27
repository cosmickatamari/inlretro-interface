#ifndef _shared_dict_stuff_h
#define _shared_dict_stuff_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// STUFF DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/stuff.c
//
//=============================================================================================
//=============================================================================================


//clear the LOWER half word, and set the upper
//should do this one first if you want to set > 16bit seed
#define		SET_LFSR_H_CLR_L	1	//operand = upper half word of LFSR
//set the LOWER half word of LFSR
#define		SET_LFSR_L		2	//operand = lower half word of LFSR
//if you don't use these setters, the seed value starts with 1
#define		RESET_LFSR		3	//sets seed to 1

#endif
