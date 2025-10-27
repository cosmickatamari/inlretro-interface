#ifndef _shared_dict_operation_h
#define _shared_dict_operation_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// OPERATION DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/operation.c
//
//=============================================================================================
//=============================================================================================

//avr definition:
//typedef struct operation_info {
enum operation_elem_nums {	//Each index is numbered by it's name
//	uint8_t		operation;	//overall type of operation being performed
			OPERATION 	= 0,
//	uint8_t		addrH_dmask;	//mask page_num lower byte to get directly addressable A15:A8 bits
			ADDRH_DMASK 	= 1,
//	uint8_t		pg2bank_shright; //shift page_num to right this many bits to get cur bank value
			PG2BANK_SHRIGHT	= 2,
//	uint8_t		valid_addr_msb;	//most significant bit that must be valid for operation (ie A14 SST)
			VALID_ADDR_MSB	= 3,
//unlock sequence SST $5555 0xAA
//	uint8_t		unlock1_bank;	//unlock sequence #1 bank number for mapper reg
			UNLOCK1_BANK	= 4,
//	uint8_t		unlock1_AH;	//unlock sequence #1 A15:A8
			UNLOCK1_AH	= 5,
//	uint8_t		unlock1_AL;	//unlock sequence #1 A7:A0
			UNLOCK1_AL	= 6,
//	uint8_t		unlock1_data;	//unlock sequence #1 D7:D0
			UNLOCK1_DATA	= 7,
////unlock sequence SST $2AAA 0x55
//	uint8_t		unlock2_bank;	//unlock sequence #1 bank number for mapper reg
			UNLOCK2_BANK	= 8,
//	uint8_t		unlock2_AH;	//unlock sequence #2 A15:A8
			UNLOCK2_AH	= 9,
//	uint8_t		unlock2_AL;	//unlock sequence #2 A7:A0
			UNLOCK2_AL	= 10,
//	uint8_t		unlock2_data;	//unlock sequence #2 D7:D0
			UNLOCK2_DATA	= 11,
////command SST byte write $5555 0xA0,  SST sector/chip erase $5555 0x80
//	uint8_t		command_bank;	//flash command bank (ie bank to write byte write, sector erase cmd)
			COMMAND_BANK	= 12,
//	uint8_t		command_AH;	//flash command A15:A8
			COMMAND_AH	= 13,
//	uint8_t		command_AL;	//flash command A7:A0
			COMMAND_AL	= 14,
//	uint8_t		command1_data;	//flash command D7:D0 command 1 data (ie SST sect erase 0x80)
			COMMAND1_DATA	= 15,
//	uint8_t		command2_data;	//flash command D7:D0 command 2 data (ie SST sect erase 0x30)
			COMMAND2_DATA	= 16,
////actual byte operation (ie Byte address bank and addr)
//	uint8_t		oper_bank;	//current bank value for actual operation to be done (ie write byte)
			OPER_BANK	= 17,
//	uint8_t		oper_AH;	//operation A15:A8 (ie actual byte write address)
			OPER_AH		= 18,
//	//uint8_t		oper_AL;	//operation A7:A0
//	//uint8_t		oper_data;	//operation D7:D0 (ie actual byte data)

			//number of byte elements in operation_data
			//since first element is zero, this will equal num byte (non-pointer)  elements
			OPER_DATA_NUM_BYTE_ELEMENTS

		//Function pointers get translated from function number to pointer within firmware
//	oper_funcptr	op_func;	//function used for overall operation
//	read_funcptr	rd_func;	//function used to read memory
//	write_funcptr	wr_mem_func;	//function used to write to memory
//	write_funcptr	wr_map_func;	//function used to write to mapper
		
};
//}operation_data;




//=============================================================================================
//	OPCODES with up to 24bit operand and optional return value  besides SUCCESS/ERROR_CODE
//	PAYLOAD options listed as well
//=============================================================================================
//	Detect this opcode/operand setup with opcode between the following defines:
//
//------------------------------------
#define OPER_OPCODE_NRV_MIN	0x00
#define OPER_OPCODE_NRV_MAX	0x3F
//------------------------------------
#define OPER_OPCODE_RV_MIN	0x40
#define OPER_OPCODE_RV_MAX	0x7F
//------------------------------------
//
//=============================================================================================
//=============================================================================================

//set buffer manager operation value
//lower operand byte sets value
#define SET_OPERATION	0x00

//set data currently stored in buff0 to operation_info elements
//This sets all byte elements, but not function pointers
#define COPY_BUFF0_TO_ELEMENTS	0x01

//copy oper info elements over to buff0
//this copies over all byte elements, but not function pointers
#define COPY_ELEMENTS_TO_BUFF0	0x02


//pass dictionary in operMSB and command/func in operLSB
#define SET_OPER_FUNC		0x03
#define SET_RD_FUNC		0x04
#define SET_WR_MEM_FUNC		0x05
#define SET_WR_MAP_FUNC		0x06


//retrieve buffer manager current operation variable
#define GET_OPERATION	0x40		//RL=3



#endif
