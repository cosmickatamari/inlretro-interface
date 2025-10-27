#ifndef _shared_dict_ciccom_h
#define _shared_dict_ciccom_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// CICCOM DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/ciccom.c
//
//=============================================================================================
//=============================================================================================

#define	CICCOM_INIT	0

#endif
