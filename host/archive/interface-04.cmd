@echo off

setlocal EnableDelayedExpansion

mkdir ignore
mkdir games
mkdir games\sram


:intro
set "cartridge="
set "sys="
cls

echo. -------------------------------
echo.  INL Retro Dumper Interface
echo.
echo.  Written By:   Cosmic Katamari
echo.  Twitter:      @cosmickatamari
echo.
echo. -------------------------------
echo.
echo.  Last Updated: (date)2019
echo.  Release 0.04
echo. -------------------------------
echo.
echo. Which console does the cartridge belong to?
echo.
echo. 1) Nintendo Entertainment System / Famicom
echo. 2) Super Nintendo Entertainment System / Super Famicom
echo. 3) Nintendo 64
echo. 4) Gameboy / Gameboy Advance
echo. 5) Sega Genesis
echo.


:select
set /p sys= "Selection: "
echo.

	if %sys% LEQ 0 goto select
	if %sys% GEQ 6 goto select


:cartridge
echo.
echo. What is the name of the cartridge?
set /p "cartridge= Name: "

	if "[%cartridge%]" EQU "[]" goto cartridge

echo.
echo. -------------------------------
echo.


	if %sys% EQU 1 goto nes
	if %sys% EQU 2 goto snes
	if %sys% EQU 3 goto n64
	if %sys% EQU 4 goto gameboy
	if %sys% EQU 5 goto sega

	
:nes

set "nesmap="
set "prg="
set "chr="
set "wram="
set "ans="


echo. For PCB information, visit BootGod's web site - 
echo. http://bootgod.dyndns.org:7777/advanced.php
echo. -------------------------------
echo. 
echo. Which Mapper does the PCB use?
echo. 01) Action53		02) Action53_TSOP	03) BNROM		04) CDREAM
echo. 05) CNINJA		06) CNROM		07) DualPort		08) EasyNSF
echo. 09) FME7		10) Mapper30		11) Mapper30v2		12) GTROM
echo. 13) MMC1		14) MMC3		15) MMC4		16) MMC5
echo. 17) NROM		18) UNROM
echo.
set /p "ans= Number: "
echo.

	if %ans% LEQ 00 goto nes
	if %ans% GEQ 19 goto nes
	
	if %ans% EQU 01 ( 
		set nesmap=Action53 
		)
		
	if %ans% EQU 02 ( 
		set nesmap=Action53_TSOP
		)
		
	if %ans% EQU 03 ( 
		set nesmap=BNROM
		)
		
	if %ans% EQU 04 ( 
		set nesmap=CDREAM
		)
		
	if %ans% EQU 05 ( 
		set nesmap=CNINJA
		)
		
	if %ans% EQU 06 ( 
		set nesmap=CNROM
		)
		
	if %ans% EQU 07 ( 
		set nesmap=DualPort
		)
		
	if %ans% EQU 08 ( 
		set nesmap=EasyNSF
		)
		
	if %ans% EQU 09 ( 
		set nesmap=FME7
		)
		
	if %ans% EQU 10 ( 
		set nesmap=Mapper30
		)
		
	if %ans% EQU 11 ( 
		set nesmap=Mapper30v2
		)
		
	if %ans% EQU 12 ( 
		set nesmap=GTROM
		)
		
	if %ans% EQU 13 ( 
		set nesmap=MMC1
		)
		
	if %ans% EQU 14 ( 
		set nesmap=MMC3
		)
		
	if %ans% EQU 15 ( 
		set nesmap=MMC4
		)
		
	if %ans% EQU 16 ( 
		set nesmap=MMC5
		)
		
	if %ans% EQU 17 (
		set nesmap=NROM
		)
		
	if %ans% EQU 18 ( 
		set nesmap=UNROM
		)

:nesprg

set /p "prg= What size (in KB) is the PRG ROM? "
echo. 

	if %prg% LEQ 7 goto nes_error_prg

:neschr_check

set /p "ans= Does the PCB have a Character (CHR) ROM? (y/n) "

	if "%ans%" EQU "n" goto neswram
	if "%ans%" EQU "y" goto neschr

:neschr

set /p "chr= What size (in KB) is the CHR ROM? "
echo.

	if %chr% LEQ 7 goto nes_error_chr

:neswram

set /p "wram= Does the PCB have save data (WRAM)? (y/n) "

	if "%wram%" EQU "n" goto neswrite
	if not "%wram%" EQU "y" goto neswram
	
:neswrite

if "%ans%" EQU "n" (
	if "%wram%" EQU "y" (
		inlretro.exe -s scripts/inlretro2.lua -c NES -m %nesmap% -x %prg% -d ".\games\%cartridge%.nes" -a ".\games\sram\%cartridge%.nes" -w 8
		)
	)
	
if "%ans%" EQU "n" (
	if "%wram%" EQU "n" (
		inlretro.exe -s scripts/inlretro2.lua -c NES -m %nesmap% -x %prg% -d ".\games\%cartridge%.nes"
		)
	)

if "%ans%" EQU "y" (
	if "%wram%" EQU "y" (
		inlretro.exe -s scripts/inlretro2.lua -c NES -m %nesmap% -x %prg% -y %chr% -d ".\games\%cartridge%.nes" -a ".\games\sram\%cartridge%.nes" -w 8
		)
	)
	
if "%ans%" EQU "y" (
	if "%wram%" EQU "n" (
		inlretro.exe -s scripts/inlretro2.lua -c NES -m %nesmap% -x %prg% -y %chr% -d ".\games\%cartridge%.nes"
		)
	)

goto ending

:snes
inlretro.exe -s scripts/inlretro2.lua -c SNES -d ".\games\%cartridge%.sfc" -a ".\games\%cartridge%.srm"

goto ending

:n64
:gameboy
:sega


:ending
echo.
echo. Starting over to dump the next cartridge.
echo. You can remove the cartridge at this time.
echo.
echo. Save files are saved to reflect compatibility with Everdrive N8.
echo. You will manually need to rename the extension if using an emulator (commonly .SAV). 
echo.

pause
goto intro

:nes_error_prg
echo. Value must be increments of 4, starting at 8.
echo. Look for the PRG0 Size Value.
echo.
goto nesprg

:nes_error_chr
echo. Value must be increments of 4, starting at 8.
echo. Look for the CHR0 Size Value.
echo.
goto neschr
