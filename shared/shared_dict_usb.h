#ifndef _shared_dict_usb_h
#define _shared_dict_usb_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields

#define RETURN_BUFF_SIZE	8	//number of bytes in generic return buffer
#define RETURN_ERR_IDX		0	//index of IN DATA stage that contains SUCCESS/ERROR#
#define RETURN_LEN_IDX		1	//index of IN DATA stage that contains length of return value(s) in bytes (0-125)
#define RETURN_DATA		2	//index of IN DATA stage that contains start of return data

//=============================================================================================
//=============================================================================================
// USB DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/usb.c
//
//=============================================================================================
//=============================================================================================

#endif
