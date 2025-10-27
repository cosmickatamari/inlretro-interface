#ifndef _shared_dict_bootload_h
#define _shared_dict_bootload_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// BOOTLOAD DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/bootload.c
// these opcodes are currently only defined for STM32 devices
// AVR devices use their own dedicated & entirely separate bootloader handled via switch
//
//=============================================================================================
//=============================================================================================


//BOOTLOAD opcodes

//could never get this to work so just going to cut it out
//#define		JUMP_BL		1	//jump to the bootloader

#define		LOAD_ADDRH	2	//upper address half word used for various functions
#define		JUMP_ADDR	3	//jump to address upper 16bit provided previous opcode

#define		PREP_FWUPDATE	4	//leave main application and sets up for fwupdate


// POINTER READ/WRITE ACCESS
// With great power comes great responsibility
// these opcodes perform direct read/write access of the STM32 address space
// you can litterally read/write any address 
// accessing restricted areas will cause hardfaults
// don't think it's really possible to brick the device using any of these
// worst case you could corrupt flash if you halfway know what you're doing
// so long as you don't mess up the option bytes to disable the BOOT pin
// you'll be able to recover the device using bootloader jumper/switch 
// via stmicro dfuse demo

// this could actually be pretty handy for mcu debugging.
// allowing for reading of registers, memory, etc between dictionary calls
//
// TODO for this use including AVR support is actually a good idea
// but need to be extra careful there as bricking an AVR could
// permanently brick it to where not even an AVR programmer could save it
// atleast the mcu socketed..  Bricking it would be difficult to do accidentally.
// More of a concern if one were tinkering with fuses and such.
// Don't feel like learning the AVR memory map enough to add this support
// at the moment.  Perhaps much of the ARM code will compile and work fine 
// on the AVR..?

//operand provides 16bit value for RD/WR commands below
#define		SET_PTR_HI	5	
#define		SET_PTR_LO	6
#define		GET_PTR		7	//RL=6

//ALL OFFSETS ARE INTERPRETED AT POSITIVE UNSIGNED!
//read 16bit value from memory location being pointed to
//operand provides offset from current pointer, but doesn't modify the pointer
#define		RD_PTR_OFFSET	8	//RL=4  0-error, 1-len, 2-LSB, 3-MSB
//operand provides 16bit value to be written, miscdata provides offset
#define		WR_PTR_OFFSET	9

//operand provides 16bit offset which is added to ptr before access
//then reads from that address
#define		RD_PTR_OFF_UP	10	//RL=4  0-error, 1-len, 2-LSB, 3-MSB

//miscdata provide 8bit offset which is added to ptr before access
//operand is the 16bit value which is written to memory location being pointed to
#define		WR_PTR_OFF_UP	11

//application code version
//this is updated more frequently than the USB firmware version
#define		GET_APP_VER	12	//RL=3  0-error, 1-len, 2-version  (2345-version if string "AV##")
//STM32 just set pointer to 0x08000800 and read 4 bytes for now
//AVR has to use this method..

	//APPLICATION VERSION NUMBERS
	//#define	APP_VERSION	"AV00"	//released with usb firmware v2.3
	//main update was addition of usb firmware updater
	//also added the bootloader pointer memory access
	//include ram functions & starting to have NES flash algos return data
	#define	APP_VERSION	3	//released 8/16 with N64 dump fix and MMC2/4 support

#endif
