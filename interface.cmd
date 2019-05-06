@echo off

setlocal
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
echo.  Last Updated: 05/05/2019
echo.  Initial Release
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
set /p "cartridge=" "Name: "

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
:snes
inlretro.exe -s scripts/inlretro2.lua -c SNES -d ".\games\%cartridge%.sfc" -a ".\games\%cartridge%.srm"

:n64
:gameboy
:sega

echo.
echo. Starting over to dump the next cartridge.
echo. You can remove the cartridge at this time.
echo.

pause
goto intro