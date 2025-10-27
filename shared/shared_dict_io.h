#ifndef _shared_dict_io_h
#define _shared_dict_io_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// IO DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/io.c
//
//=============================================================================================
//=============================================================================================


//pullup as many cart pins as possible
//goal to be safe state for all hardware
//LED is pulled up (DIM) to help indicate this io state
//FFs are disabled due to pull up on /OE
#define IO_RESET	0	
	//operand: 1-disable STM SW DEBUG PORT in the process
	//SWD & SWC pins have default GPIO settings different from all others
	//this sets a static variable so anytime the firmware calls io_reset
	//the debug remains disabled.  But if the host calls IO_RESET
	//whatever operand is provided is set.
	#define	DISABLE_STM_DEBUG	0x10
	//sending no operand (0) clears the disable debug setting in firmware
	

//NES cartridge interfacing setup
//set outputs as required
//latch address of $0000
//disable NES cart memories
#define NES_INIT	1

//SNES cartridge interfacing setup
//set outputs as required
//latch address of $000000
//disable cart memories
//reset high disables SRAM and puts INL carts in PRGM mode
#define SNES_INIT	2

//SWIM protocol init
//"single wire interface module"
//different INL boards have this signal on different pins
//So initialization must provide pin to perform all subsequent
//communications with
#define SWIM_INIT	3
	//	don't define    0x00 to protect from forgetting to pass swim lane
	#define	SWIM_ON_A0	0x01	//NES & Famicom carts
	#define	SWIM_ON_EXP0	0x02	//SNES carts
	#define	SWIM_ON_D0	0x03	//NES discrete CICOprocessor


//JTAG protocol init
//4 wire serial protocol for configuring and communicating to programmable logic device cores
//different INL boards have this signal on different pins or virtual CIC ports
//So initialization must provide pins to perform all subsequent
//communications with
#define JTAG_INIT	4
	//	don't define    0x00 to protect from forgetting to pass jtag lane
	#define	JTAG_ON_EXP0_3	0x01	//Most NES carts with CPLDs EXP0-TDO, EXP1-TDI, EXP2-TMS, EXP3-TCK
	#define JTAG_ON_SNES_CTL	0x02	//SNES v2.0proto2 SYSCLK-TCK, RESET/EXP0-TMS, WR-TDI, RD-TDO



#define GAMEBOY_INIT	5
#define GBA_INIT	6
#define SEGA_INIT	7
#define N64_INIT	8

//default is 3v by pulling up on GBP pin
//these set GBP pin to output and drive high for 3v, and low for 5v
//be careful not to drive GBA cartridge with 5v as it's supposed to only be 3v
#define GB_POWER_5V	9
#define GB_POWER_3V	10




//Test EXP0 drive with pull up 
//This is an important test if reling on pulling up EXP0 pin to drive the cart's pin.
//EXP0 is used for various things and may have pull up/down of it's own or significant load
//Test that programmer can drive EXP0 with a pull up before reling on commands that only pullup
//If this fails, can resort to driving EXP0 with SNES /RESET commands but excersize caution
//as some NES cart's have CPLD JTAG TDO pin placed on EXP0 that may not be 5v tolerant.
//FC also has APU audio placed on EXP0, carts without exp sound short RF sound (EXP6) to EXP0
//So if EXP FF's output is enabled, driving the mcu EXP0 pin could cause damage to the pin.
//that's why it's best in general to only pull up EXP0 instead of driving it high.
//Have to drive it low however to get logic 0 most times.  If famicom cart is inserted,
//it's probably safer to drive EXP0 through EXP6 sound jumper and leave EXP0 floating/pulledup.
//
//Test starts by verifying EXP0 can be driven low, if not, will return one byte of AUX_PIN
//followed by alternating 0xAA, 0x55, 0xAA...
//This test pulls up EXP0 and then reads AUX_PIN 6 times in rapid succession returning error code
//plus 6 bytes of read data.  If pull up works but is just slow, should see that in return data.
//data[0] marks bit where EXP0 resisdes to provide host with bitmask for EXP0
#define EXP0_PULLUP_TEST	0x80	//RL=3
	//return values
	#define EXP0_STUCK_HI		0xF0
	#define CANNOT_PULLUP_EXP0	0xE0
	//if 0-20, denotes number of cycles it took
	//AVR appears to have weaker pullup than stm	
//without any cart inserted takes 5 cycles for EXP0 to settle high
//with discrete NROM board inserted (has pullup on EXP0) settled immediately
//SNES board inserted never settled
//famicom NROM choplifter cart inserted never settled
//INLXO-ROM board JTAG TDO (non-5v tolerant) tied to EXP0 settled immediately



#endif
