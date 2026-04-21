#include "usb_operations.h"

static libusb_device_handle *lua_usb_handle = NULL;

//control transfer request types
//uint8_t libusb_control_setup::bmRequestType
//Request type.
//	Bits 0:4 determine recipient, see libusb_request_recipient. Bits 5:6 determine type, see libusb_request_type. Bit 7 determines data transfer direction, see libusb_endpoint_direction.
//
//libusb_request_types:
//LIBUSB_REQUEST_TYPE_STANDARD	Standard handled by driver during setup/etc
//LIBUSB_REQUEST_TYPE_CLASS 	Class for use with specific device classes like HID.
//LIBUSB_REQUEST_TYPE_VENDOR	Vendor application specific as we choose which is what we'll be utilizing for all transfers
//LIBUSB_REQUEST_TYPE_RESERVED	Reserved. 
//
//libusb_request_recipients:
//LIBUSB_RECIPIENT_DEVICE	Device.
//LIBUSB_RECIPIENT_INTERFACE	Interface.
//LIBUSB_RECIPIENT_ENDPOINT	Endpoint.
//LIBUSB_RECIPIENT_OTHER	Other. 
//
//LIBUSB_ENDPOINT_IN		In: device-to-host.
//LIBUSB_ENDPOINT_OUT		Out: host-to-device. 

libusb_device_handle *open_usb_device( libusb_context *context, int log_level )
{	
	int rv = 0;
	libusb_device_handle *handle = NULL;
	libusb_device **device_list = NULL;

	//context set to NULL since only acting as single user of libusb
	//libusb_context *context = NULL;
	//passed in from main

	if (log_level>0) printf("Initalizing libusb\n");
	//initialize libusb must be called prior to any other libusb function
	//returns 0 on success LIBUSB_ERROR code on failure
	//int libusb_init ( libusb_context **  context) 
	int usb_init = libusb_init(&context);
	check( usb_init == LIBUSB_SUCCESS, "Failed to initialize libusb: %s", libusb_strerror(usb_init));
	if (log_level>0) printf("Successfully initalized libusb\n");

	//void libusb_set_debug ( libusb_context *  ctx, int  level ) 
	if ( log_level>0) {
		printf("setting LIBUSB_LOG_LEVEL to: %d\n", log_level);
		switch ( log_level) {
			case 1:
			printf("\tERROR: error messages are printed to stderr\n");
			break;
			case 2:
			printf("\tWARNING: warning and error messages are printed to stderr\n");
			break;
			case 3:
			printf("\tINFO: informational, warning, & error messages are printed to stdout\n");
			break;
			case 4:
			default:
			printf("\tDEBUG: debug, info, warning, & error messages are printed to stdout\n");
			break;
		}
	}
	libusb_set_debug(context, log_level);

	//discover all usb devices
	//ssize_t libusb_get_device_list (libusb_context *ctx, libusb_device ***list)
	// Returns a list of USB devices currently attached to the system.
	// return value is number of devices plus one as list is null terminated, or LIBUSB_ERROR if negative.
	// Must free device list after done with it
	if (log_level>0) printf("Getting USB device list\n");
	int dev_count = libusb_get_device_list( context, &device_list);
	check( dev_count >= 0, "libusb unable to find any devices: %s", libusb_strerror(dev_count));
	if (log_level>0) printf("Successfully retrieved USB device list\n");

	int i = 0;

	libusb_device *retroprog = NULL;
	libusb_device *device = NULL;
	struct libusb_device_descriptor desc;
	const char manf[256];	//used to hold manf/prod strings
	const char prod[256];	//used to hold manf/prod strings
		//Original kazzo
		// manf_ascii: obdev.at prod_ascii: kazzo bcd Device: 100
		//INL Retro-Prog v1.0
		// manf_ascii: InfiniteNesLives.com prod_ascii: INL Retro-Prog bcd Device: 100
		//INL Retro-Prog v2.0 v2.0 released late 2016 (only ver supported by this app
		// manf_ascii: InfiniteNesLives.com prod_ascii: INL Retro-Prog bcd Device: 200
	const char *kazzo_manf = "obdev.at";
	const char *kazzo_prod = "kazzo";
	const char *inl_manf = "InfiniteNesLives.com";
	const char *rprog_prod = "INL Retro-Prog";
	uint16_t min_fw_ver = 0x200;

	if (log_level>0) printf("Searching %d total devices\n", dev_count-1);
	for( i=0; i<dev_count; i++) {
		device = device_list[i];
		if (log_level>0) printf("getting dev desc #%d ", i);
		rv = libusb_get_device_descriptor( device, &desc);
		check( rv == LIBUSB_SUCCESS, "Unable to get device #%d descriptor: %s", i, libusb_strerror(rv));
				
		if (log_level>0) printf("checking %x vendor ", desc.idVendor);
		if (log_level>0) printf("checking %x product\n", desc.idProduct);
		if ((desc.idVendor == 0x16C0) && (desc.idProduct == 0x05DC)) {
			//Found a V-USB device with default VID/PID now see if it's actually a kazzo
			//printf("found matching VID PID pair\n");
			if (log_level>0) printf("found vend ID:%x prod ID:%x ", desc.idVendor, desc.idProduct);
			if (log_level>0) printf("manf: %d prod: %d\n", desc.iManufacturer, desc.iProduct);

			//opening device allows performing I/O via USB with device
			rv = libusb_open( device, &handle );
			check( rv == LIBUSB_SUCCESS, "Unable to open USB device: %s., \n\nDEVICE FOUND, BUT CAN'T OPEN DEVICE, VERIFY DRIVERS ARE INSTALLED!!!", libusb_strerror(rv));
			if (log_level>0) printf("device opened successfully\n");

			if (desc.iManufacturer) {
				if ( libusb_get_string_descriptor_ascii( handle, 
					desc.iManufacturer, (unsigned char *)manf, sizeof(manf) ) > LIBUSB_SUCCESS) {
					if (log_level>0) printf("manf_ascii: %s\n",manf);
				} else {
					printf("\nMatching PID/VID found and opened, but unable to communicate to device, verify drivers installed!!!\n\n");
				}
			}
			if (desc.iProduct) {
				if ( libusb_get_string_descriptor_ascii( handle, 
					desc.iProduct, (unsigned char *)prod, sizeof(prod) ) > LIBUSB_SUCCESS) {
					if (log_level>0) printf("prod_ascii: %s\n",prod);
				}
			}

			//Now that manf and prod ID's have been retrieved determine if it's a kazzo/retroprog
			if ( strcmp( manf, kazzo_manf) == 0) {
				if ( strcmp( prod, kazzo_prod) == 0) {
					log_warn("Original kazzo found, firmware needs updated.");
				}
			}

			if ( strcmp( manf, inl_manf) == 0) {
				if (log_level>0) printf("INL manufactured device found\n");
				if ( strcmp( prod, rprog_prod) == 0) {
					if (log_level>0) printf("INL Retro-Prog found\n");
					if (log_level>0) printf("bcd Device fw version: %x required: %x\n", desc.bcdDevice, min_fw_ver);
					if (desc.bcdDevice < min_fw_ver) { 
						//close device since can't use it
						log_warn("INL Retro-Prog found, but firmware is too old, see Readme for instructions to update firmware.");
					} else {
						//Finally found the supported device!!!
						retroprog = device;
						break;
					}
				}
			}
			//Getting here means the device was opened because it matched V-USB
			//VID/PID, but it wasn't a compatible device.	
			//Can't use this device, so close it
			if (log_level>0) printf("VID/PID matched, but manf/prod didn't match, closing device.\n It's likely that the drivers haven't been installed...\n");
			libusb_close(handle);
			handle = NULL;	//Don't want to try and reclose
		}
	}
	//looped through all devices retroprog will be assigned if it was found.
	check( retroprog != NULL, "Could not find INL retro-prog USB device");
	if (log_level>0) printf("INL retro-prog USB device successfully found\n");

	//free device list now that INL retro-prog was found and opened
	//void libusb_free_device_list ( libusb_device **  list, int  unref_devices ) 
	if (log_level>0) printf("Freeing USB device list\n");
	libusb_free_device_list( device_list, 1);	//don't completely understand the unref_devices = 1...
	device_list = NULL; //denote that device list is free if end up in error
	//Guess this is what you're supposed to do..
	// the process of opening a device can be viewed as follows:
	//
	//     Discover devices using libusb_get_device_list().
	//     Choose the device that you want to operate, and call libusb_open().
	//     Unref all devices in the discovered device list.
	//     Free the discovered device list.
	//
	//     The order is important - you must not unreference the device before attempting to open it, because unreferencing it may destroy the device.
	//
	//     For convenience, the libusb_free_device_list() function includes a parameter to optionally unreference all the devices in the list before freeing the list itself. This combines steps 3 and 4 above.
	//
	//     As an implementation detail, libusb_open() actually adds a reference to the device in question. This is because the device remains available through the handle via libusb_get_device(). The reference is deleted during libusb_close(). 

	//report successful connection to INL retro-prog
	printf("Successfully discovered and connected to INL retro-prog:\n");//TODO with firmware version 2.0\n");
	printf("Device firmware version: %x.%x.x \n", (desc.bcdDevice>>8), (desc.bcdDevice&0x00FF) );

	//free device list if it was left open
	if (device_list) {
		log_err("USB Device list wasn't freed, freeing device list\n");
		libusb_free_device_list( device_list, 1);
	}

	if (log_level>0) printf("Returning device handle to main\n");

	//set this module's pointer to handle so it can be referenced by lua
	lua_usb_handle = handle;

	return handle;

error:
	printf("open_usb_device went to error\n");

	if (device_list) {
		printf("freeing device list\n");
		libusb_free_device_list( device_list, 1);
	}

	if (handle) {
		printf("closing usb device\n");
		libusb_close(handle);
	}

	if (usb_init == LIBUSB_SUCCESS) {
		printf("deinitializing libusb\n");
		libusb_exit(context);
	}

	if (rv == LIBUSB_ERROR_ACCESS) {
		printf("-------------------------------------------------------\n");
		printf("Denied Permission is expected for initial use on Linux.\n");
		printf("See udev-rule-help/Readme.txt in host dir for help gaining permission.\n");
		printf("Try command with sudo for a cheap temporary solution.\n");
	}

	return NULL;	//Return NULL pointer if couldn't find INL Retro-Prog
}

void close_usb(libusb_context *context, libusb_device_handle *handle) 
{
	//must close device before exiting
	libusb_close(handle);
	handle = NULL;	//delete handle reference so error won't retry closing

	//deinitialize libusb to be called after closing all devices and before teminating application
	libusb_exit(context);
	
	return;
}


/*	USB transfer 
 *Desc:	primary means of sending and recieving commands and data to retro programmer
 *	makes calls to libusb drivers to send/recieve control transfer setup, data, and status packets
 *	See USBtransfer struct explaination in usb_operations.h for more details
 *Pre:	libusb must be initialized
 *	USBtransfer struct must be initialized as follows:
 *	-handle must point to open usb device
 *	-endpoint "direction" must be defined 
 *	-request must be a valid and defined in a command dictionary
 *	-wValue and wIndex must be valid as defined by request dictionary
 *	-WLength must equal number of bytes to be transferred with max of 254
 *	-data points to buffer of raw data to send for reads or dump into for reads
 *		if wLength is zero, data can be NULL
 *Post: USB control transfer complete (setup, data, and status packets)
 *	data buffer pointed by USBtransfer struct filled with read data for USB_IN requests.
 *	USBtransfer struct is unmodified can be reused for identical transfers with different payload	
 *	libusb is still initialized and open
 *Rtn:	Number of bytes transferred on success (positive)
 *	ERROR if unable to transfer USBtransfer's wLength number of bytes
 *	prints libusb_error if there was usb problem
 */
int usb_vendor_transfer( USBtransfer *transfer )
{
	check( transfer->wLength <= MAX_VUSB, "Can't transfer more than %d bytes!", MAX_VUSB);
	//check( transfer->wLength <= MAX_VUSB_LONGXFR, "Can't transfer more than %d bytes!", MAX_VUSB_LONGXFR);

	if ( transfer->wLength != 0) {
		check( transfer->data != NULL, "data buffer isn't initialized it's: %s", transfer->data);
	} else {
		debug("USB transfer with no data payload.");
	}
	//TODO create a check to verify dictionary is defined, and opcode/operands are valid
	//TODO also check to ensure opcode supports endpoint direction
	//many operations could be performed with IN/OUT and no data packet
	//but all avr operations should have a return value success/error code
	//one way to control whether those retrun values are read back is endpoint direction

	uint16_t wValue = transfer->wValue;
//	wValue = wValue << 8;
//	wValue |= transfer->wValueLSB;

	uint16_t wIndex = transfer->wIndex;
//	wIndex = wIndex << 8;
//	wIndex |= transfer->wIndexLSB;

	debug("reqtype   h: %x \n", ( LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_RECIPIENT_DEVICE | transfer->endpoint));
	debug("request   h: %x d: %d", transfer->request, transfer->request);
	debug("wValueMSB h: %x d: %d", transfer->wValueMSB, transfer->wValueMSB);
	debug("wValueLSB h: %x d: %d", transfer->wValueLSB, transfer->wValueLSB);
	debug("wValue    h: %x", wValue); 
	debug("wValue    d: %d", wValue);
	debug("wIndexMSB h: %x d: %d", transfer->wIndexMSB, transfer->wIndexMSB);
	debug("wIndexLSB h: %x d: %d", transfer->wIndexLSB, transfer->wIndexLSB);
	debug("wIndex    h: %x", wIndex);
	debug("wIndex    d: %d", wIndex);

	int xfr_cnt = libusb_control_transfer( 
			transfer->handle, 
			//Request type: vendor (as we define),  recip: device, out: host->device
			//LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_RECIPIENT_DEVICE | LIBUSB_ENDPOINT_OUT, 
			LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_RECIPIENT_DEVICE | transfer->endpoint, 
			//request, wValue, wIndex, data, len, SEC_5);
			transfer->request, 
			wValue, wIndex,
			transfer->data, 
			transfer->wLength, 
			TIMEOUT_1_SEC);

	debug("%d bytes transfered", xfr_cnt);
	check( xfr_cnt >=0, "Write xfr failed with libusb error: %s", libusb_strerror(xfr_cnt));
	check( xfr_cnt == transfer->wLength, "Write transfer failed only %d Bytes sent expected %dBytes", 
				xfr_cnt, transfer->wLength);

	return xfr_cnt;

error:
	return -1;
}


//	initialize usb transfer based on args passed in from lua and transfer setup packet over USB

int lua_usb_vend_xfr (lua_State *L) {
/*
typedef struct USBtransfer {
	libusb_device_handle *handle;
	uint8_t		endpoint;
	uint8_t		request;
	uint16_t	wValue;
	uint16_t	wIndex;
	uint16_t	wLength;
	unsigned char	*data;
} USBtransfer;
*/
	uint8_t	data_buff[MAX_VUSB];
	int	i;
	const	char *lua_out_string;
	int xfr_count = 0; //return count
	int rv = 0;		//number of return values

	USBtransfer usb_xfr;
	usb_xfr.handle = lua_usb_handle;
	usb_xfr.endpoint	= luaL_checknumber(L, 1); /* get endpoint argument */
	usb_xfr.request		= luaL_checknumber(L, 2); /* get request argument */
	usb_xfr.wValue 		= luaL_checknumber(L, 3); /* get wValue argument */
	usb_xfr.wIndex		= luaL_checknumber(L, 4); /* get wIndex argument */
	usb_xfr.wLength		= luaL_checknumber(L, 5); /* get wLength argument */
	check( (usb_xfr.wLength <= MAX_VUSB), "Can't transfer more than %d bytes!", MAX_VUSB);
	if ( usb_xfr.endpoint == LIBUSB_ENDPOINT_OUT ) {
		//OUT transfer sending data to device
		lua_out_string = luaL_checkstring(L, 6); /* get data argument */
		//2 rules for lua strings in C: don't pop it, and don't modify it!!!
		//copy lua string over to data buffer
		for( i=0; i<usb_xfr.wLength; i++) {
			data_buff[i] = lua_out_string[i];
		}	
	} else {
		//IN transfer, zero out buffer
		for( i=0; i<MAX_VUSB; i++) {
			data_buff[i] = 0;
		}

	}
	usb_xfr.data = data_buff;


	//printf("\nep %d, req %d", usb_xfr.endpoint, usb_xfr.request);
	//printf("wValue %d, wIndex %d", usb_xfr.wValue, usb_xfr.wIndex);
	//printf("wLength %d \n", usb_xfr.wLength);
	//printf("predata: %d, %d, %d, %d, %d, %d, %d, %d \n",  usb_xfr.data[0], usb_xfr.data[1],usb_xfr.data[2],usb_xfr.data[3],usb_xfr.data[4],usb_xfr.data[5], usb_xfr.data[6], usb_xfr.data[7]);

	check( lua_usb_handle != NULL, "usb device handle pointer not initialized.\n")

	xfr_count = usb_vendor_transfer( &usb_xfr);

	//printf("postdata: %d, %d, %d, %d, %d, %d, %d, %d \n",  usb_xfr.data[0], usb_xfr.data[1],usb_xfr.data[2],usb_xfr.data[3],usb_xfr.data[4],usb_xfr.data[5], usb_xfr.data[6], usb_xfr.data[7]);
	//printf("bytes xfrd: %d\n", xfr_count);

	lua_pushnumber(L, xfr_count); /* push first result */
	rv++;

	if ( usb_xfr.endpoint == LIBUSB_ENDPOINT_IN ) {
		//push second result if data was read from device
		lua_pushlstring(L,(const char*) data_buff, xfr_count);
		rv++;
	}

	return rv; /* number of results */

error:
	printf("lua USB transfer went to error\n");
	lua_pushstring(L, "ERROR"); /* push result */
	return 1;

}
