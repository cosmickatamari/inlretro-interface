#ifndef _shared_dict_snes_h
#define _shared_dict_snes_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// SNES DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/snes.c
//
//=============================================================================================
//=============================================================================================


//set A16-23 aka bank number
#define SNES_SET_BANK			0x00

//read from current bank at provided address
//SNES reset is unaffected
#define SNES_ROM_RD			0x01	//RL=3

//write from current bank at provided address
//SNES reset is unaffected
#define SNES_ROM_WR			0x02

#define FLASH_WR_5V			0x03	//5v PLCC flash algo
#define FLASH_WR_3V			0x04	//3v TSSOP flash algo

//similar to ROM RD/WR above, but /ROMSEL doesn't go low
#define SNES_SYS_RD			0x05	//RL=3
#define SNES_SYS_WR			0x06


#endif
