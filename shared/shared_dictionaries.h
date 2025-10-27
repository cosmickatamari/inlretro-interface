#ifndef _shared_dictionaries_h
#define _shared_dictionaries_h

//list of dictionary reference numbers
//these numbers literally sent in usb control transfer in request field
//the included dictionaries define opcodes and operands contained in transfer wValue wIndex fields
//they also define expected data buffer sizes and contents.

//These dictionaries are imported to the device firmware at compile time
//The host application loads & parses these dictionaries at run time
//So creation of new dictionaries/opcodes requires device firmware to 
//be recompiled, and loaded onto the device.  But the host application
//does not need to be recompiled.
//
//
//There are a number of updates that must be completed when creating new dictionaries:
//
//1: Define the dictionary number here in this file with #define & #include
//	This will get the new dictionary included in the firmware build
//	the assigned dictionary number must be between 0-255 
//	This number is the actual USB bRequest value for the setup packet
//
//2: Create new "shared_dict_<name>.h" file in the same directory as this file
//	Feel free to copy paste a similar dict, just make sure everything is 
//	appropriately renamed in the file
//
//3: Add the new dictionary to host/scripts/app/dict.lua 
//	This includes instantiating, creating, & exporting the module at the bottom
//	of dict.lua file as follows:
//		op_<name> = {}
//		create_dict_tables( op_<name>, "../shared/shared_dict_<name>.h")
//		dict.<name> = <name>
//   Create the <name> dictionary function in dict.lua
//   	This is the function that the host scripts use each time an opcode is
//   	called for that dictionary.  It designates how the operand, misc, & data
//   	for the opcode are defined and how they map to the USB setup & data packets.
//   	Currently there is no generic function for dictionaries to use
//   	This is because some dictionaries may handle USB transfers in special ways
//   	For now one can probably get by copy pasting one of the other functions
//   	like nes, and then renaming all "nes" to "<name>" and "NES" to "<NAME>"
//   	TODO: create generic dictionary script function for general use
//
//4: Define the desired opcodes in the newly created shared/shared_dict_<name>.h file
//	This is done with lines like the following:
//	#define	NEW_OPCODE	1	//RL=2
//	the opcode name comes first which is the name used to call the opcode
//		This is used in host scripts and device firmware
//		An underscore can be tacked to the end to allow direct mapping between
//		firmware defines and shared defines (see firmware/source/pinport.h for example)
//		In that case the trailing underscore is trimmed by the host parser
//	choose an arbitrary number between 0-255 that is different from all other
//		opcodes in that dictionary
//		This value is sent as USB setup packet wValue LSByte
//	the "RL=<number>" that's follows the "//" C comment designates the "return data length"
//		This C comment is for the host side only so it knows the desired USB endpoint & data length.
//		If left out, the default is RL=1 which is ENDPOINT IN with data length of 1.
//		A negative value for RL denotes ENDPOINT OUT (write to device). 
//		a positive is ENDPOINT IN (read data from device).
//		That 1 byte of data read back from the device is typically the success/error
//		code sent back from the device to denote if opcode wasn't found, or other problem.
//		If you want some actual data to be returned increased.
//		Typically the first byte is still reserved for error code, second byte gives data length 
//		of the data that follows.  So 1 byte of return data would be RL=3
//		first byte would be errorcode, second = 1, and third byte would be actual data
//			see nes.c for an example of this on reads
//		You must also dictate what to do with that data once it arrives in the
//		dict.lua function created in step 3 above.
//		dict.lua parses this RL value, all that really matters is it follows //
//		and contains RL=<number> where the number is assumed decimal, but can be hex with 0x prefix
//		white space is okay, and RL doesn't have to be first thing in the comment
//		If one wants to comment out opcodes it must be done with // at the beginning of the line.
//		multiline C comments is not permitted by the dict.lua parser
//	Make notes about the opcode explaining operands and data when used.
//	Comments in shared_dict_<name>.h must be single line C comments starting with //
//
//5: Add support for the dictionary in the device 
//	This is done in firmware/source/usb.c within the usbFunctionSetup function
//	This is where setup packet is mapped to the firmware function you'd like to be called for 
//		each incoming setup packet for this dictionary
//
//6: Create the firmware C code to implement the dictionary.
//	Something like <name>.c & <name>.h which can be copied from a similar dictionary
//	The .h file must be included in usb.h
//	Create a <name>_call function in <name>.c which you called in step 6 above.
//	Use a switch statement to key off the opcode and pass operands/data to the opcode's function
//	Be sure to return SUCCESS/ERROR when possible to get some sort of report back from device that
//	the opcode was found and executed properly.
//	the return SUCCESS/ERROR is not possible when sending data packets to device (ENDPOINT OUT)
//	in that case perhaps you want a 'GET_LAST_ERROR_CODE' opcode that would follow afterwards..
//	These error codes should be kept in  shared/shared_errors.h
//
//7: Call opcodes in the new dictionary from host lua scripts!
//	For example: 
//	dict.io("NES_INIT")
//	calls the NES_INIT opcode in the io dictionary, this opcode happens to initialize
//	the mcu GPIO pins to a known state to prepare for calling other opcodes in the nes dictionary
//
//	dict.nes("NES_CPU_WR", 0x8000, 0xFF)
//	calls the NES_CPU_WR opcode from the nes dictionary, with operand 0x8000, and miscdata 0xFF
//	the host/scripts/app/dict.lua nes function is what determines how that operand/misc data is sent in the setup packet
//	in this example the value 0xFF is written to CPU address $8000
//
//	dict.snes("SNES_SET_BANK", 0)
//	rv = dict.snes("SNES_ROM_RD", 0xFFFF)
//	the SNES_SET_BANK opcode sets the SNES bank address bits to 0
//	the second SNES_ROM_RD opcode reads the value from $FFFF (of the currently selected bank)
//	and the read value is stored in the variable rv for use in the script
//
//	hex & decimal values can be used in data, operands, misc.  Hex must have 0x prefix
//	this is lua code afterall, so anything that's possible in lua can be done here on the host side



//Notes:
//	each unique read/write function in avr takes about 50 bytes...

//don't define dictionary #0 as it is common to forget to define 

//=============================================================================================
//=============================================================================================
#define DICT_PINPORT 1
#include "shared_dict_pinport.h"
//pinport dictionary has various commands giving low and mid level access to retro prog's i/o pins.
//See abstraction layer port definitions in firmware pinport_al.h file for more details.
//An effort has been made to make opcodes in this dictionary hardware independent.
//=============================================================================================
//=============================================================================================


//=============================================================================================
//=============================================================================================
#define DICT_IO 2
#include "shared_dict_io.h"
//io dictionary contains commands 
//Scope of functions contained is intended to be general and generic not specific
//to the cartridge inserted.  The closest these operations get to being cart/system
//specific is in setup for a system.  Calling the cart/system setup contained here
//prepares kazzo for system specific commands.  Once complete with system specifc
//commands come back here to 'deinitialize' access to that cartridge.
//commands in this dictionary are meant to estabilish baseline rules of i/o to 
//support calling higher level system/cart specific functions.
//=============================================================================================
//=============================================================================================


//=============================================================================================
//=============================================================================================
#define DICT_NES 3
#include "shared_dict_nes.h"
//nes dictionary contains commands 
//These commands rely on io initialization from io dictionary prior to calling
//This library is intended to contain all NES related opcodes/commands
//=============================================================================================
//=============================================================================================


//=============================================================================================
//=============================================================================================
#define DICT_SNES 4
#include "shared_dict_snes.h"
//snes dictionary contains commands 
//These commands rely on io initialization from io dictionary prior to calling
//This library is intended to contain all SNES related opcodes/commands
//=============================================================================================
//=============================================================================================


//=============================================================================================
//=============================================================================================
#define DICT_BUFFER 5
#include "shared_dict_buffer.h"
//mcu buffer dictionary commands 
//This library is intended to contain all buffer related opcodes/commands
//also contains defines for both host and firmware such as buffer status numbers
//=============================================================================================
//=============================================================================================


//=============================================================================================
//=============================================================================================
#define DICT_USB 6
#include "shared_dict_usb.h"
//currently no actual dictionary as there are no opcodes.
//just used to return status of usbfunctions in event of a transfer error. 
//contains definitions of data transactions between host and firmware
//=============================================================================================
//=============================================================================================


//=============================================================================================
//=============================================================================================
#define DICT_OPER 7
#include "shared_dict_operation.h"
//dictionary used to initialize and control operation_info variables
//=============================================================================================
//=============================================================================================


//=============================================================================================
//=============================================================================================
#define DICT_SWIM 8
#include "shared_dict_swim.h"
//dictionary used to control swim communications
//=============================================================================================
//=============================================================================================


//=============================================================================================
//=============================================================================================
#define DICT_JTAG 9
#include "shared_dict_jtag.h"
//dictionary used to control jtag communications
//=============================================================================================
//=============================================================================================


//=============================================================================================
//=============================================================================================
#define DICT_BOOTLOAD 10
#include "shared_dict_bootload.h"
//dictionary used to control USB device bootloader
//=============================================================================================
//=============================================================================================


//=============================================================================================
//=============================================================================================
#define DICT_CICCOM 11
#include "shared_dict_ciccom.h"
//dictionary used to communicate to the CIC 
//The lockout microcontroller on some INL manufactured cartridges
//is used for advanced features such as mirroring software switch, JTAG interface, etc.
//=============================================================================================
//=============================================================================================

//=============================================================================================
//=============================================================================================
#define DICT_GAMEBOY 12
#include "shared_dict_gameboy.h"
//gameboy dictionary 
//These commands rely on io initialization from io dictionary prior to calling
//=============================================================================================
//=============================================================================================

//=============================================================================================
//=============================================================================================
#define DICT_GBA 13
#include "shared_dict_gba.h"
//gameboy advance dictionary
//These commands rely on io initialization from io dictionary prior to calling
//=============================================================================================
//=============================================================================================

//=============================================================================================
//=============================================================================================
#define DICT_SEGA 14
#include "shared_dict_sega.h"
//Sega Genesis dictionary
//These commands rely on io initialization from io dictionary prior to calling
//=============================================================================================
//=============================================================================================

//=============================================================================================
//=============================================================================================
#define DICT_N64 15
#include "shared_dict_n64.h"
//Nintendo 64 dictionary
//These commands rely on io initialization from io dictionary prior to calling
//=============================================================================================
//=============================================================================================


//=============================================================================================
//=============================================================================================
#define DICT_FWUPDATE 16
#include "shared_dict_fwupdate.h"
//dictionary used to control self updating firmware functions
//These commands aren't actually processed by the main application
//they are sniffed out by the device's usb code and handled separately
//this is because we are presumedly erasing the main application code
//=============================================================================================
//=============================================================================================

//=============================================================================================
//=============================================================================================
#define DICT_STUFF 17
#include "shared_dict_stuff.h"
//miscelaneous stuff dictionary if you just need a few small calls that
//you don't want to create a specific dictionary for you can stuff
//them here.
//=============================================================================================
//=============================================================================================


#endif
