@echo off

setlocal
setlocal enabledelayedexpansion

mkdir ignore
mkdir games


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
echo.  Last Updated: 05/07/2019
echo.  Release 0.02
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

	if "[%cartridge%]" == "[]" goto cartridge

echo.
echo. -------------------------------
echo.


	if %sys% == 1 goto nes
	if %sys% == 2 goto snes
	if %sys% == 3 goto n64
	if %sys% == 4 goto gameboy
	if %sys% == 5 goto sega

	
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
echo. 09) FME7		10) Mapper30		11) Mapper30v2		12) MM2
echo. 13) MMC1		14) MMC3		15) MMC4		16) MMC5
echo. 17) NROM		18) UNROM
echo.
set /p "ans= Number: "
echo.

	if %ans% LEQ 00 goto nes
	if %ans% GEQ 19 goto nes
	
	if %ans% == 01 ( 
		set nesmap = "Action53" 
		)
		
	if %ans% == 02 ( 
		set nesmap = "Action53_TSOP"
		)
		
	if %ans% == 03 ( 
		set nesmap = "BNROM"
		)
		
	if %ans% == 04 ( 
		set nesmap = "CDREAM"
		)
		
	if %ans% == 05 ( 
		set nesmap = "CNINJA"
		)
		
	if %ans% == 06 ( 
		set nesmap = "CNROM"
		)
		
	if %ans% == 07 ( 
		set nesmap = "DualPort"
		)
		
	if %ans% == 08 ( 
		set nesmap = "EasyNSF"
		)
		
	if %ans% == 09 ( 
		set nesmap = "FME7"
		)
		
	if %ans% == 10 ( 
		set nesmap = "Mapper30"
		)
		
	if %ans% == 11 ( 
		set nesmap = "Mapper30v2"
		)
		
	if %ans% == 12 ( 
		set nesmap = "MM2"
		)
		
	if %ans% == 13 ( 
		set nesmap = "MMC1"
		)
		
	if %ans% == 14 ( 
		set nesmap = "MMC3"
		)
		
	if %ans% == 15 ( 
		set nesmap = "MMC4"
		)
		
	if %ans% == 16 ( 
		set nesmap = "MMC5"
		)
		
	if %ans% == 17 ( 
		set nesmap = "NROM"
		)
		
	if %ans% == 18 ( 
		set nesmap = "UNROM"
		)

goto nesprg

:nesprg

set /p "prg= What size (in KB) is the PRG ROM? "
echo.

	if %prg% LEQ 7 goto nes_error_prg

:neschr_check

set /p "ans= Does the PCB have a Character (CHR) ROM? (y/n) "
echo.

	if "%ans%" == "n" goto neswram
	if "%ans%" == "y" goto neschr

:neschr

set /p "chr= What size (in KB) is the CHR ROM? "
echo.

	if %chr% LEQ 7 goto nes_error_chr

:neswram

set /p "wram= Does the PCB have save data (WRAM)? (y/n) "
echo.

	if "%wram%" == "n" goto neswrite
	if not "%wram%" == "y" goto neswram
	
:neswrite

if "%ans%" == "n" (
	if "%wram%" == "y" (
		echo inlretro.exe -s scripts/inlretro2.lua -c NES -m %nesmap% -x %prg% -d ".\games\%cartridge%.nes" -a ".\games\%cartridge%.sav" -w 8
		)
	)
	
if "%ans%" == "n" (
	if "%wram%" == "n" (
		echo inlretro.exe -s scripts/inlretro2.lua -c NES -m %nesmap% -x %prg% -d ".\games\%cartridge%.nes"
		)
	)

if "%ans%" == "y" (
	if "%wram%" == "y" (
		echo inlretro.exe -s scripts/inlretro2.lua -c NES -m %nesmap% -x %prg% -y %chr% -d ".\games\%cartridge%.nes" -a ".\games\%cartridge%.sav" -w 8
		)
	)
	
if "%ans%" == "y" (
	if "%wram%" == "n" (
		echo inlretro.exe -s scripts/inlretro2.lua -c NES -m %nesmap% -x %prg% -y %chr% -d ".\games\%cartridge%.nes"
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
