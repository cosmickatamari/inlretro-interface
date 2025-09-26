# INL Retro Dumper Interface
# By Cosmic Katamari (@cosmickatamari)
# Last Updated: 09/15/2025

# PowerShell 7.5.x check
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Checking for and creating dumping folder locations.
$null = New-Item -ItemType Directory -Path ".\ignore" -Force
$null = New-Item -ItemType Directory -Path ".\games\nes\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\snes\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\n64\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\gameboy\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\genesis\sram" -Force

$NESmapperMenu = @(
    'Action53',
    'Action53_TSOP',
    'BNROM',
    'CDREAM',
    'CNINJA',
    'CNROM',
    'DualPort',
    'EasyNSF',
    'FME7',
	'GTROM',
    'Mapper30',
    'Mapper30v2',
    'MMC1',
	'MMC2',
    'MMC3',
    'MMC4',
    'MMC5',
    'NROM',
    'UNROM', 
	'UNROM_TSOP'
)

$consoleMap = @{
	1 = "Nintendo Entertainment System"
	2 = "Super Nintendo Entertainment System"
	3 = "Nintendo 64"
	4 = "Gameboy"
	5 = "Sega Genesis"
}

function Read-Int([string]$prompt){
    while($true){
        $v = Read-Host $prompt
        if([int]::TryParse($v, [ref]([int]$null))){
            return [int]$v
        }
        Write-Host "Please enter a valid selection." -ForegroundColor Yellow
    }
}

function Read-YesNo([string]$prompt){
    while($true){
        $v = (Read-Host "$prompt (y/n)").Trim().ToLower()
        if($v -in @('y','n')){ return $v }
        Write-Host "Please enter Y or N." -ForegroundColor Yellow
    }
}

function Read-KB-MultipleOf4([string]$prompt){
    while($true){
        $v = Read-Int $prompt
        if($v -ge 8 -and $v % 4 -eq 0){ return $v }
        Write-Host "Value must be increments of 4, starting with 8." -ForegroundColor Yellow
    }
}

function Run-INL([string]$argsLine){
	Write-Host "inlretro.exe $argsLine"
    Write-Host ">> inlretro.exe $argsLine"
    & .\inlretro.exe $argsLine.Split(' ')
    if($LASTEXITCODE -ne 0){
        Write-Host "inlretro.exe exited with code $LASTEXITCODE." -ForegroundColor Red
    }
}

function Pause-Continue {
    Read-Host
}

function Show-Header {
    Clear-Host
	Write-Host "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-"
    Write-Host "INL Retro Dumper Interface"
    Write-Host "Created By:   	Cosmic Katamari"
    Write-Host "X/Twitter:    	@cosmickatamari"
    Write-Host "`nLast Updated: 	9/14/2025"
    Write-Host "Release: 	0.10"
    Write-Host "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-"
}

function Select-Console {
    Write-Host "`n`nSelect A Console" -ForegroundColor Blue
    Write-Host
    Write-Host " 1 - Nintendo Entertainment System" -ForegroundColor Yellow
    Write-Host " 2 - Super Nintendo Entertainment System" -ForegroundColor Yellow
    Write-Host " 3 - Nintendo 64" -ForegroundColor DarkGray
    Write-Host " 4 - Gameboy / Gameboy Advance" -ForegroundColor DarkGray
    Write-Host " 5 - Sega Genesis" -ForegroundColor DarkGray
    Write-Host
	
    while ($true) {
        $choice = Read-Int "Selection"
        if ($consoleMap.ContainsKey($choice)) {
            return $consoleMap[$choice]
        }
        else {
            Write-Host "Please choose a between 1-5." -ForegroundColor Yellow
        }
    }
}

function Get-CartridgeName {
    while($true){
        $name = Read-Host "`nWhat is the name of your $sys game?"
        if([string]::IsNullOrWhiteSpace($name)){ continue }
        return $name.Trim()
    }
}

function Select-Mapper {
    Write-Host "`nYour default web browser has opened the NES database. `nUsing the (Game Title) search field, retrieve detailed information about your game cartridge." -ForegroundColor Magenta
    Write-Host "`nWhich Mapper (hardware) does the cartridge use?"

    $columns = 5

    # Find the widest entry (number + name) so padding fits
    $maxLen = 0
    for ($i = 0; $i -lt $NESmapperMenu.Count; $i++) {
        $num = ($i+1).ToString("00")
        $entry = " {0}. {1}" -f $num, $NESmapperMenu[$i]
        if ($entry.Length -gt $maxLen) { $maxLen = $entry.Length }
    }
    $colWidth = $maxLen + 4  # add some extra spacing

    # Print mappers in table format
    for ($i = 0; $i -lt $NESmapperMenu.Count; $i++) {
        $num = ($i+1).ToString("00")
        $text = " {0}. {1}" -f $num, $NESmapperMenu[$i]
        Write-Host ($text.PadRight($colWidth)) -NoNewline

        if ( (($i+1) % $columns) -eq 0 ) {
            Write-Host
        }
    }
    
	Write-Host  # final newline for incomplete rows

    while ($true) {
        $ans = Read-Int "`nMapper Number"
        if ($ans -ge 1 -and $ans -le $NESmapperMenu.Count) {
            return $NESmapperMenu[$ans-1]
        }
        Write-Host ("Please choose between 1-{0}." -f $NESmapperMenu.Count) -ForegroundColor Yellow
    }
}

while($true){
    Show-Header
    $sys = Select-Console
    $cartridge = Get-CartridgeName
	# Start-Process "https://nescartdb.com/search" -WindowStyle Minimized

    switch($sys){
		'Nintendo Entertainment System' {
            $nesmap = Select-Mapper
            $prg = Read-KB-MultipleOf4 "`nWhat is the size (in KB) of the PRG-ROM (usually PRG0)?"

            $hasChr = Read-YesNo "`nDoes the cartridge have a Character (CHR) ROM? (usually CHR0)"
            $chr = $null
            if($hasChr -eq 'y'){
                $chr = Read-KB-MultipleOf4 "What is the size (in KB) of the CHR-ROM?"
            }

            $hasSRAM = Read-YesNo "`nDoes the cartridge maintain save data (WRAM)?"

            $cartdest = ".\games\nes\$cartridge.nes"
            $sramdest = ".\games\nes\sram\$cartridge.nes"

            # Build argument list matching the original CMD logic
            if($hasChr -eq 'n'){
                if($hasSRAM -eq 'y'){
                    Run-INL "-s scripts/inlretro2.lua -c NES -m $nesmap -x $prg -d `"$cartdest`" -a `"$sramdest`" -w 8"
                } else {
                    Run-INL "-s scripts/inlretro2.lua -c NES -m $nesmap -x $prg -d `"$cartdest`""
                }
            } else {
                if($hasSRAM -eq 'y'){
                    Run-INL "-s scripts/inlretro2.lua -c NES -m $nesmap -x $prg -y $chr -d `"$cartdest`" -a `"$sramdest`" -w 8"
                } else {
                    Run-INL "-s scripts/inlretro2.lua -c NES -m $nesmap -x $prg -y $chr -d `"$cartdest`""
                }
            }
		
			Write-Host "`nYour cartridge dump is located at $cartdest." -ForegroundColor Cyan
	
			if($hasSRAM -eq 'y'){
				Write-Host "Your save data is located at $sramdest." -ForegroundColor Green
			} else {}
			
			Write-Host "`nIt is safe to remove the cartridge." -ForegroundColor Cyan
			Pause-Continue
        }
		
        2 {  # SNES
            $dest = ".\games\snes\$cartridge.sfc"
            $sram = ".\games\snes\sram\$cartridge.srm"
            Run-INL "-s scripts/inlretro2.lua -c SNES -d `"$dest`" -a `"$sram`""
            Pause-Continue
        }
        3 {  # N64 (placeholder)
            Write-Host "Add args as needed." -ForegroundColor Yellow
            Pause-Continue
        }
        4 {  # Gameboy / GBA (placeholder)
            Write-Host "Add args as needed." -ForegroundColor Yellow
            Pause-Continue
        }
        5 {  # Sega Genesis (placeholder)
            Write-Host "Add args as needed." -ForegroundColor Yellow
            Pause-Continue
        }
	}
}