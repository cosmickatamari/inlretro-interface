# Build inlretro.exe from source/inlprog.c (MinGW or MSYS2).
#
# Prerequisites: gcc, GNU make, and libusb-1.0 (headers in host/include; link per below).
#   MSYS2 UCRT64: pacman -S mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-libusb
#   Then: mingw32-make
#
# If linking fails with "cannot find -lusb-1.0", place libusb-1.0.dll in this directory
# (see repo host/libusb-1.0.dll). GNU make will link against that DLL automatically.
# Or set explicitly: mingw32-make USB_LIB=libusb-1.0.dll
# Or use an import lib: mingw32-make USB_LIB=C:/path/to/libusb-1.0.dll.a
#
# MinGW often lacks `cc`; this Makefile defaults CC to gcc.
#
# After building, run `.\inlretro.exe -h` and confirm -k line mentions N64 auto-detect
# (scripts/n64/basic.lua). If you still see "non-NES systems" only, the .exe is stale.

ROOT := ..
LUA_DIR := source/lua
# GNU make defaults CC=cc; MinGW often has no cc.exe — force gcc (override with: mingw32-make CC=...)
CC = gcc
CFLAGS := -std=gnu99 -O2 -Wall -Iinclude -Isource -I$(LUA_DIR) -I$(ROOT)/shared
ifneq ($(wildcard libusb-1.0.dll),)
USB_LIB ?= libusb-1.0.dll
else
USB_LIB ?= -lusb-1.0
endif
LDLIBS := $(USB_LIB) -lws2_32

.PHONY: all clean lua-lib

all: inlretro.exe

lua-lib:
	$(MAKE) -C $(LUA_DIR) liblua.a

inlretro.exe: lua-lib source/inlprog.o source/usb_operations.o
	$(CC) -o $@ source/inlprog.o source/usb_operations.o $(LUA_DIR)/liblua.a $(LDLIBS)

source/inlprog.o: source/inlprog.c
	$(CC) $(CFLAGS) -c -o $@ $<

source/usb_operations.o: source/usb_operations.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	$(RM) source/inlprog.o source/usb_operations.o inlretro.exe
	$(MAKE) -C $(LUA_DIR) clean
