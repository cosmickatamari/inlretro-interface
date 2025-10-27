#ifndef _shared_dict_nes_h
#define _shared_dict_nes_h

//define dictionary's reference number in the shared_dictionaries.h file
//then include this dictionary file in shared_dictionaries.h
//The dictionary number is literally used as usb transfer request field
//the opcodes and operands in this dictionary are fed directly into usb setup packet's wValue wIndex fields


//=============================================================================================
//=============================================================================================
// NES DICTIONARY
//
// opcodes contained in this dictionary must be implemented in firmware/source/nes.c
//
//=============================================================================================
//=============================================================================================


//	OPCODES with no operand and no return value besides SUCCESS/ERROR_CODE

//Discrete board PRG-ROM only write, does not write to mapper
//This is a /WE controlled write with data latched on rising edge EXP0
//PRG-ROM /WE <- EXP0 w/PU
//PRG-ROM /OE <- /ROMSEL
//PRG-ROM /CE <- GND
//PRG-ROM write: /WE & /CE low, /OE high
//mapper '161 CLK  <- /ROMSEL
//mapper '161 /LOAD <- PRG R/W
//wValueMSB: data
//wIndex: address
#define DISCRETE_EXP0_PRGROM_WR		0x00

#define NES_PPU_WR			0x01

//generic CPU write with M2 toggle as expected with NES CPU
// A15 decoded to enable /ROMSEL as it should
#define NES_CPU_WR			0x02

//#define DISCRETE_EXP0_MAPPER_WR		0x03

//write to an MMC1 register, provide bank/address & data
#define NES_MMC1_WR			0x04

#define NES_DUALPORT_WR			0x05

#define DISC_PUSH_EXP0_PRGROM_WR	0x06


#define MMC3_PRG_FLASH_WR		0x07	//TODO set return lengths for all these functions
#define MMC3_CHR_FLASH_WR		0x08
#define NROM_PRG_FLASH_WR		0x09
#define NROM_CHR_FLASH_WR		0x0A
#define CNROM_CHR_FLASH_WR		0x0B	//needs cur_bank & bank_table prior to calling
#define CDREAM_CHR_FLASH_WR		0x0C	//needs cur_bank & bank_table prior to calling
#define UNROM_PRG_FLASH_WR		0x0D	//needs cur_bank & bank_table prior to calling
#define MMC1_PRG_FLASH_WR		0x0E
#define MMC1_CHR_FLASH_WR		0x0F	//needs cur_bank set prior to calling
#define MMC4_PRG_SOP_FLASH_WR		0x10	//current bank must be selected, & needs cur_bank set prior to calling
#define MMC4_CHR_FLASH_WR		0x11	//needs cur_bank set prior to calling
#define MAP30_PRG_FLASH_WR		0x12	//needs cur_bank set prior to calling
#define GTROM_PRG_FLASH_WR		0x13	//desired bank must be selected
#define MMC4_PRG_FLASH_WR		0x14	//mapper mod to XOR A14 with A13


#define	SET_CUR_BANK			0x20
#define	SET_BANK_TABLE			0x21

#define M2_LOW_WR			0x22	//like CPU WR, but M2 stays low

//write a page worth of random data to ppu
//make sure the LSFR is initialized first in misc dict
//send start address in operand, doesn't have to be page boundary
//but A13 and /A13 get set once based on provided address.
#define	PPU_PAGE_WR_LFSR		0x23	

#define	SET_NUM_PRG_BANKS		0x24	//used for determining banktable structure for mapper 11 and such
#define M2_HIGH_WR			0x25	//like CPU WR, but M2 stays high
#define FLASH_3V_WR			0x25	//same as above but easier to remember when 
						//being used to write to 3v tssop flash
#define MMC3S_PRG_FLASH_WR		0x26	//TODO set return lengths for all these functions


//=============================================================================================
//	OPCODES WITH OPERAND AND RETURN VALUE plus SUCCESS/ERROR_CODE
//=============================================================================================

//read from NES CPU ADDRESS
//set /ROMSEL, M2, and PRG R/W
//read from cartridge just as NES's CPU would
//nice and slow trying to be more like the NES
#define EMULATE_NES_CPU_RD		0x80	//RL=3

//like the one above but not so slow..
#define NES_CPU_RD			0x81	//RL=3

#define NES_PPU_RD			0x82	//RL=3

//doesn't have operands just returns sensed CIRAM A10 mirroring 
//now used to detect old firmware versions so NESmaker folks don't have to update firmware
#define CIRAM_A10_MIRROR		0x83	//RL=3
////returns VERT/HORIZ/1SCNA/1SCNB values:
//	#define	MIR_1SCNA	0x10
//	#define	MIR_1SCNB	0x11
//	#define	MIR_VERT	0x12
//	#define	MIR_HORZ	0x13

#define NES_DUALPORT_RD			0x84	//RL=3

#define	GET_CUR_BANK			0x85	//RL=3
#define	GET_BANK_TABLE			0x86	//RL=4 16bit value so 2 bytes need returned
#define	GET_NUM_PRG_BANKS		0x87	//RL=3 

#define MMC5_PRG_RAM_WR			0x88	//RL=3 Enable writting to PRG-RAM and then write a single byte
						//after written read back for verification as a timeout would cause fail

#endif
