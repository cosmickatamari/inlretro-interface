# INL Retro Dumper Interface
# By: Cosmic Katamari (@cosmickatamari)

# PowerShell 7.5.x check
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Global Variables
$NESCARTDBOpened = 0

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
        if($v -ge 0 -and $v % 0 -eq 0){ return $v }
        Write-Host "Value must be increments of 4, starting with 8." -ForegroundColor Yellow
    }
}

function Run-INL {
    param([string[]]$ArgsArray)

    $pretty = (
        $ArgsArray | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"','`"') + '"' } else { $_ }
        }
    ) -join ' '

    Write-Host "`nProgram and argument call used:" -ForegroundColor Blue
	Write-Host ".\inlretro.exe $pretty" -ForegroundColor Blue
	& (Join-Path $PSScriptRoot 'inlretro.exe') @ArgsArray

    if ($LASTEXITCODE -ne 0) {
        Write-Host "inlretro.exe exited with code $LASTEXITCODE." -ForegroundColor Red
		Write-Host "`nThe cartridge could not be dumped." -ForegroundColor Red
		} else {
		
		Write-Host "`nYour cartridge has been dumped to the location: $cartdest." -ForegroundColor Green
		
		if ($hasSRAM -eq 'y') {
			Write-Host "Your save data has been stored in: $sramdest." -ForegroundColor Green
		}
		
		Write-Host "`nIt is safe to remove the cartridge." -ForegroundColor Cyan
		Write-Host "Pressing [ENTER] will restart the application, allowing for the next cartridge to be dumped." -ForegroundColor Cyan
	}
	
	Pause-Continue
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
    Write-Host "`nLast Updated: 	9/16/2025"
    Write-Host "Release: 	0.05"
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
	$baseurl = "https://nescartdb.com/search/basic?keywords="
	$endurl = "&kwtype=game"
	Start-Process $baseurl+$cartridge+$endurl -WindowStyle Minimized
	$script:NESCARTDBOpened = $true

	Clear-Host
    Write-Host "`nYour default web browser has opened the NES database for the cartidge title $cartridge" -ForegroundColor Blue
    Write-Host "`nWhich Mapper (PCB Class) does the cartridge use?"

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
    
	Write-Host "`nFor ANROM cartridges, select the option for BNROM."

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
	
    switch($sys){
		'Nintendo Entertainment System' {
			$nesmap = Select-Mapper
			$prg    = Read-KB-MultipleOf4 "`nWhat is the size (in KB) of the Program (PRG) ROM? (typically PRG0)"
			$hasChr	= Read-YesNo "`nDoes the cartridge have a Character (CHR) ROM? (typically CHR0)"
			$chr	= $null
			
			if ($hasChr -eq 'y') { 
				$chr = Read-KB-MultipleOf4 "What is the size (in KB) of the Character ROM?" 
				}

			$hasSRAM = Read-YesNo "`nDoes the cartridge contain a battery save (Working RAM)?"

			# Paths for storing files.
			$gamesRoot = Join-Path $PSScriptRoot 'games\nes'
			$cartdest  = Join-Path $gamesRoot "$cartridge.nes"
			$sramdest  = Join-Path (Join-Path $gamesRoot 'sram') "$cartridge.srm"

			# Arguments passed to the executable.
			$argsArray = @(
				'-s', (Join-Path $PSScriptRoot 'scripts\inlretro2.lua')
				'-c', 'NES'
				'-m', "$nesmap"
				'-x', "$prg"
				'-d', "$cartdest"
			)

			if ($hasChr -eq 'y') { 
				$argsArray += @('-y', "$chr") 
				}
				
			if ($hasSRAM -eq 'y') { 
				$argsArray += @('-a', "$sramdest", '-w', '8') 
				}

			Run-INL $argsArray
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