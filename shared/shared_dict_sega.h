#ifndef _shared_dict_sega_h
#define _shared_dict_sega_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// SEGA (genesis/megadrive) DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/sega.c
//
//=============================================================================================
//=============================================================================================

//TODO THESE ARE JUST PLACE HOLDERS...
//oper=A1-15 update firmware address variable for FLASH_WR_ADDROFF use on subsequent calls
#define	GEN_SET_ADDR	0
//oper=A1-A16 C_CE & C_OE go low (update firmware address var ie GEN_SET_ADDR)
#define	GEN_ROM_RD	1	//RL=4 return error code, data len = 1, 2 byte of data (16bit word)

// GENESIS ADDR A17-23 along with #LO_MEM & #TIME
// TODO separate #LO_MEM & #TIME, they're currently fixed high
#define GEN_SET_BANK 2	

//miscdata=D0-7, oper=A1-A16 C_CE & C_OE go low, #LDSW goes low (update firmware address var ie GEN_SET_ADDR)
#define	GEN_WR_LO	3
//miscdata=D8-15, oper=A1-A16 C_CE & C_OE go low, #UDSW goes low (update firmware address var ie GEN_SET_ADDR)
#define	GEN_WR_HI	4
//oper=D0-D15, miscdata=addroffset C_CE & C_OE go low, #UDSW goes low (update firmware address var ie GEN_SET_ADDR)
#define	GEN_FLASH_WR_ADDROFF	5


#define	GEN_SST_FLASH_WR_ADDROFF	6

#endif
