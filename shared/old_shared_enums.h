#ifndef _shared_enums_h
#define _shared_enums_h

//One concise place to list all enums used 
//for setting cartridge and memory elements on the host
//which end up getting communicated between device and host

//used to denote when any cartridge element is not known
#define UNKNOWN 	0xFF	

//console options
#define NES_CART 	'N'
#define FC_CART 	'F'
#define SNES_CART 	'S'
#define BKWD_CART 	'B'

//NES mappers
#define NROM	0
#define MMC1	1
#define CNROM	2
#define UxROM	3
#define MMC3	4
#define MMC5	5
#define AxROM	7
#define MMC2	9
#define MMC4	10
#define CDREAMS	11
#define A53	28
#define UNROM512 30
#define EZNSF	31
#define BxROM	34
#define RAMBO	64
#define H3001	65	//IREM mapper
#define GxROM	66
#define SUN3	67
#define SUN4	68
#define FME7	69	//SUNSOFT-5 with synth
#define HDIVER	78
#define DxROM	205
//	UNKNOWN 255	don't assign to something meaningful

enum mirroring {
	MIR_1SCNA = 0x10,	//SCNA
	MIR_1SCNB = 0x11,	//SCNB
	MIR_VERT  = 0x12,	//VERT
	MIR_HORIZ = 0x13,	//HORIZ
	MIR_ANROM,
	MIR_MMC1,
	MIR_MMC3,
	MIR_FME7
};

enum operations {
	READ = 10,
	WRITE,	
	CHECK
};

//SST 39SF0x0 manf/prod IDs
#define SST_MANF_ID	0xBF
#define SST_PROD_128	0xB5
#define SST_PROD_256	0xB6
#define SST_PROD_512	0xB7


//SRAM manf/prod ID
#define SRAM	0xAA

//MASK ROM read only
#define MASKROM	0xDD

enum buff_mem_type {
	PRGROM = 10,
	CHRROM,
	PRGRAM,
	SNESROM,
	SNESRAM
};

//buffer/operation status values
#define EMPTY 		0x00
#define RESET		0x01
#define PROBLEM		0x10
#define PREPARING	0x20
#define USB_UNLOADING	0x80
#define USB_LOADING	0x90
#define USB_FULL	0x98
#define CHECKING	0xC0
#define DUMPING		0xD0
#define STARTDUMP	0xD2
#define DUMPED		0xD8
#define ERASING		0xE0
#define FLASHING	0xF0
#define STARTFLASH	0xF2
#define FLASHED		0xF4
#define FLASH_WAIT	0xF8
#define STOPPED		0xFE
#define UNALLOC 	0xFF

enum addr_high_direct_mask {
 //actual value is part mapper dependent and part flash dependent
        //mapper controlled address bits dictate where split is
        //32KB banking A14-0 NES ctl, A15+ mapper ctl "bank" NROM, BNROM, ANROM
        //addrH_dmask   = 0b0111 1111 directly addressable addrH bits
	MSK_32KB = 0x7F,
        //16KB banking A13-0 NES ctl, A14+ mapper ctl "bank" UxROM, MMC1
        //addrH_dmask   = 0b0011 1111
	MSK_16KB = 0x3F,
        // 8KB banking A12-0 NES ctl, A13+ mapper ctl "bank" MMC3, FME7, CHR discrete banking
        //addrH_dmask   = 0b0001 1111
	MSK_8KB  = 0x1F,
        // 4KB banking A11-0 NES ctl, A12+ mapper ctl "bank" ezNSF MMC1 CHR
        //addrH_dmask   = 0b0000 1111
	MSK_4KB  = 0x0F,
        // 2KB banking A10-0 NES ctl, A11+ mapper ctl "bank" MMC3 CHR
        //addrH_dmask   = 0b0000 0111
	MSK_2KB  = 0x07,
        // 1KB banking A9-0 NES ctl, A10+ mapper ctl "bank" FME7 CHR
        //addrH_dmask   = 0b0000 0011
	MSK_1KB  = 0x03
};

enum page2bankshiftright {
        //A15->A8 = 7 shifts (equal to number of set bits in addrH_mask
	PG2B_32KB = 7,
        //A14->A8 = 6 shifts
	PG2B_16KB = 6,
        //A13->A8 = 5 shifts
	PG2B_8KB = 5,
        //A12->A8 = 4 shifts
	PG2B_4KB = 4,
        //A11->A8 = 3 shifts
	PG2B_2KB = 3,
        //A10->A8 = 2 shifts
	PG2B_1KB = 2
};

#endif
