#ifndef _shared_dict_pinport_h
#define _shared_dict_pinport_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// PINPORT DICTIONARY
//=============================================================================================
//=============================================================================================

//This file was created based on firmware version of pinport.h and pinport.c
//the close relationship between these two files must be kept in mind when making changes.
//This file is also very dependent on macro definitions in firmware.
//Any changes to this file must be applied to firmware.
//Don't recommend changing opcodes or anything here, change them in fw first then apply here.
//making this a shared file helps cut room for error as changing opcode numbers here will
//inherently get forwarded to both firmware and app at same time.
//
//Trailing underscores are trimmed from this file for the host application to allow direct 
//between firmware and host software.  Firmware only uses defines with trailing underscores
//for opcode/operand decoding.
//




//=============================================================================================
//	OPCODES with
//=============================================================================================
//
//=============================================================================================
//=============================================================================================

//============================
//CONTROL PORT INDIVIDUAL PIN ACCESS
//opcode: type of pin operation
//operand: pin to act on
//============================

//opcodes
#define	CTL_ENABLE_	0
#define	CTL_IP_PU_	1
#define	CTL_IP_FL_	2
#define	CTL_OP_		3
#define	CTL_SET_LO_	4
#define	CTL_SET_HI_	5
#define	CTL_RD_		6	//RL=4	(error code, data length, LSB, MSB)
#define	CTL_OD_		24
#define	CTL_PP_		25
	//operands
//	PC0  "M2"	NES M2/phi signal
	#define	C0_		0
	#define	M2_		0
//	PC1  "ROMSEL"	Cartridge rom enable
	#define	C1_		1
	#define	ROMSEL_		1
//	PC2  "PRGRW"	NES CPU R/W signal
	#define	C2_		2
	#define	PRGRW_		2
//	PC3  "FREE"	purple kazzo EXP flipflop latch, FREE on most AVR/adapter kazzos
	#define	C3_		3
	#define	FREE_		3
//	PC4  "CSRD"	NES CHR/SNES /RD
	#define	C4_		4
	#define	CSRD_		4
//	PC5  "CSWR"	NES CHR/SNES /WR
	#define	C5_		5
	#define	CSWR_		5
//	PC6  "CICE" 	NES CIRAM /CE
	#define	C6_		6
	#define	CICE_		6
//	PC7  "AHL" 	ADDR HI Latch
	#define	C7_		7
	#define	AHL_		7
//	PC8  "EXP0" 	NES EXP0, cart-console /RESET
	#define	C8_		8
	#define	EXP0_		8
	#define	SNES_RST_	8
//	PC9  "LED" 	kazzos tied this to NES EXP9, INL6 connects to CIC CLK
	#define	C9_		9
	#define	LED_		9
//	PC10 "IRQ"	console CPU interrupt from cart
	#define	C10_		10
	#define	IRQ_		10
//	PC11 "CIA10" 	NES CIRAM A10
	#define	C11_		11
	#define	CIA10_		11
//	PC12 "BL" 	Bootloader pin 
	#define	C12_		12
	#define	BL_		12
//	PC13 "AXL" 	EXP FF latch and /OE, purple kazzos this was only /OE
	#define	C13_		13
	#define	AXL_		13
//	 INLretro6 adds following pins
//	PC14 "AUDL"	cart audio
	#define	C14_		14
	#define	AUDL_		14
//	PC15 "AUDR"	cart audio
	#define	C15_		15
	#define	AUDR_		15
//	PC16 "GBP"	GB power selector
	#define	C16_		16
	#define	GBP_		16
//	PC17 "SWD" 	mcu debug
	#define	C17_		17
	#define	SWD_		17
//	PC18 "SWC" 	mcu debug
	#define	C18_		18
	#define	SWC_		18
//	PC19 "AFL" 	flipflop addr expansion for FF0-7 (also CIC RESET on NES)
	#define	C19_		19
	#define	AFL_		19
//	PC20 "COUT" CIC data out
	#define	C20_		20
	#define	COUT_		20
//	PC21 "FCAPU" cart audio in
	#define	C21_		21
	#define	FCAPU_		21
//	 INLretro6 gains direct control over NES EXP port and is used for N64 control pins:
//	PCxx "D8" 
//	#define	Cxx_		xx
//	PC22 "D9" 
	#define	C22_		22
//	PC23 "D10" 
	#define	C23_		23
//	PC24 "D11" 
	#define	C24_		24
//	PC25 "D12" 
	#define	C25_		25
//	PC26 "D13" 
	#define	C26_		26
//	PC27 "D14" 
	#define	C27_		27

//		D15 & D16 are defined as CICE/CIA10 above
	#define	C28_		28
	#define	C29_		29

//============================
//DATA PORT BYTE WIDE ACCESS
//opcode: type of pin operation
//operand: value to place on bus
//============================
#define	DATA_ENABLE_	7
#define	DATA_IP_PU_	8
#define	DATA_IP_	9
#define	DATA_OP_	10
#define	DATA_SET_	11
#define	DATA_RD_ 	12	//RL=3 (error code, data length, databyte)

//============================
//ADDR PORT 16bit WIDE ACCESS
//opcode: type of operation
//operand: value to place on bus
//============================
#define ADDR_ENABLE_	13
#define ADDR_PU_	14
#define ADDR_IP_	15
#define ADDR_OP_	16
#define ADDR_SET_	17
#define ADDR_RD_	26	//doesn't work on devices without direct access to 16bit address bus

//============================
//EXP PORT 8bit ACCESS (bits1-8)
//opcode: type of operation
//operand: value to place on bus
//============================
#define EXP_ENABLE_	18
#define EXP_DISABLE_	19
#define EXP_SET_	20

//============================
//HIGH ADDR PORT 8bit WIDE ACCESS
//opcode: type of operation
//operand: value to place on bus
//============================
#define HADDR_ENABLE_	21
#define HADDR_DISABLE_	22
#define HADDR_SET_	23

//	CTL_OD_		24 above
//	CTL_PP_		25 above
//	ADDR_RD_	26 above

//============================
//FLIPFLOP ADDR PORT 8bit WIDE ACCESS
//SEGA: FF0-7 connecto to A17-18, #AS, A20-23, #TIME
//opcode: type of operation
//operand: value to place on bus
//NOTE: these operations corrupt the ADDR bus, so call this first 
//============================
#define FFADDR_ENABLE_	27
#define FFADDR_DISABLE_	28
#define FFADDR_SET_	29

#endif
