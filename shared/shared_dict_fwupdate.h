#ifndef _shared_dict_fwupdate_h
#define _shared_dict_fwupdate_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// FIRMWARE UDPATE DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source_stm_only/fwupdate.c
// dictionary used to control self updating firmware functions
// These commands aren't actually processed by the main application
// they are sniffed out by the device's usb code and handled separately
// this is because we are presumedly erasing the main application code
//
//=============================================================================================
//=============================================================================================


//send the 1KByte page address to be erased CANNOT send page 0 or 1 as this is where usb & fwupdater is
//RB has 2KByte pages so the page numbers are off, and 2KByte will be erased per command
//C6 has 1KByte pages which is more aligned with how this function operates
//The argument is effectively A10-A26 of the mcu memory map starting with offset 0x0800_0000
//ie sending 2 to a C6 erases 0x0800_0800 through 0x0800_0BFF
//ie sending 2 to a RB erases 0x0800_0800 through 0x0800_0FFF
//ie sending 3 to a C6 erases 0x0800_0C00 through 0x0800_0FFF
//ie sending 3 to a RB erases 0x0800_0800 through 0x0800_0FFF (same as 2)
//you can pretend they're the same if you always send the odd page that follows the even
//this will be redundant for the RB erasing the same page twice, but make them behave the same
//you can effectively ignore the odd pages on RB, or pretend the page number is shifted right by 1
#define		ERASE_1KB_PAGE	1	//erase any page except the first 2KByte

//Don't actually want to leave the flash in an unlocked state
//it's fast to unlock/lock so just do it before each flash operation
//#define		UNLOCK_FLASH	2
//#define		LOCK_FLASH	3

#define		WR_HWORD	4	//operand = data, miscdata = offset from FLASH->AR

//FLASH->AR seems to drop the upper 16bits of address when flash is unlocked...
//but it's still there apparently when accessed internally for flashing halfwords..?
#define		GET_FLASH_ADDR	5	//RL = 6  0-SUCCESS 1-len 2-LSB 3, 4, 5-MSB

//SET FLASH->AR to an address that's currently erased
// 0x08 8bitmiscdata 16bitoperand
// this also unlocks then locks the flash and writes 0xFFFF to the address selected
// C6 only has 32KByte of flash, so miscdata must be zero
// operand MUST BE EVEN! writes must be half word aligned
#define		SET_FLASH_ADDR	6	//only works if the 

#define		GET_FLASH_DATA	7	//RL = 4  0-SUCCESS 1-len 2-LSB 3-MSB
//similar to above, but provide an address, FLASH->AR is unchanged
//can generically read from any flash address
// ADDRESS: 0x08 8bitmiscdata 16bitoperand
// this could be used to dump the entire contents of the flash
#define		READ_FLASH	8	//RL = 4  0-SUCCESS 1-len 2-LSB 3-MSB

//device issues system reset to itself
//don't want to do this until the main application has been reprogrammed
#define		RESET_DEVICE	9

#endif
