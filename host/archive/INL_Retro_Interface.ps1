# INL Retro Dumper Interface (PowerShell port)
# Original batch by Cosmic Katamari (@cosmickatamari)
# Ported to PowerShell by ChatGPT (GPT-5 Thinking)
# Last Updated: 2025-09-14

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Ensure folders exist
$null = New-Item -ItemType Directory -Path ".\ignore" -Force
$null = New-Item -ItemType Directory -Path ".\games" -Force
$null = New-Item -ItemType Directory -Path ".\games\sram" -Force

function Read-Int([string]$prompt){
    while($true){
        $v = Read-Host $prompt
        if([int]::TryParse($v, [ref]([int]$null))){
            return [int]$v
        }
        Write-Host "Please enter a number." -ForegroundColor Yellow
    }
}

function Read-YesNo([string]$prompt){
    while($true){
        $v = (Read-Host "$prompt (y/n)").Trim().ToLower()
        if($v -in @('y','n')){ return $v }
        Write-Host "Please enter y or n." -ForegroundColor Yellow
    }
}

function Pause-Continue {
    Write-Host
    Read-Host "Press ENTER to continue"
}

function Show-Header {
    Clear-Host
    Write-Host "-------------------------------"
    Write-Host " INL Retro Dumper Interface"
    Write-Host
    Write-Host " Written By:   Cosmic Katamari"
    Write-Host " Twitter:      @cosmickatamari"
    Write-Host
    Write-Host "-------------------------------"
    Write-Host
    Write-Host " Last Updated: 2019 (original)"
    Write-Host " Release 0.04 (batch)"
    Write-Host " PowerShell port: 2025-09-14"
    Write-Host "-------------------------------"
    Write-Host
}

$mapperMenu = @(
    'Action53',
    'Action53_TSOP',
    'BNROM',
    'CDREAM',
    'CNINJA',
    'CNROM',
    'DualPort',
    'EasyNSF',
    'FME7',
    'Mapper30',
    'Mapper30v2',
    'MM2',
    'MMC1',
    'MMC3',
    'MMC4',
    'MMC5',
    'NROM',
    'UNROM'
)

function Select-Console {
    Write-Host "Which console does the cartridge belong to?"
    Write-Host
    Write-Host " 1) Nintendo Entertainment System / Famicom"
    Write-Host " 2) Super Nintendo Entertainment System / Super Famicom"
    Write-Host " 3) Nintendo 64"
    Write-Host " 4) Gameboy / Gameboy Advance"
    Write-Host " 5) Sega Genesis"
    Write-Host
    while($true){
        $sys = Read-Int 'Selection'
        if($sys -ge 1 -and $sys -le 5){ return $sys }
        Write-Host "Please choose 1-5." -ForegroundColor Yellow
    }
}

function Get-CartridgeName {
    while($true){
        $name = Read-Host "What is the name of the cartridge?"
        if([string]::IsNullOrWhiteSpace($name)){ continue }
        return $name.Trim()
    }
}

function Select-Mapper {
    Write-Host
    Write-Host "For PCB information, visit BootGod's site:"
    Write-Host "http://bootgod.dyndns.org:7777/advanced.php"
    Write-Host "-------------------------------"
    Write-Host
    Write-Host "Which Mapper does the PCB use?"
    for($i=0; $i -lt $mapperMenu.Count; $i++){
        $num = ($i+1).ToString("00")
        Write-Host (" {0}) {1}" -f $num, $mapperMenu[$i])
    }
    while($true){
        $ans = Read-Int "Number"
        if($ans -ge 1 -and $ans -le $mapperMenu.Count){
            return $mapperMenu[$ans-1]
        }
        Write-Host ("Please choose 1-{0}." -f $mapperMenu.Count) -ForegroundColor Yellow
    }
}

function Read-KB-MultipleOf4([string]$prompt){
    while($true){
        $v = Read-Int $prompt
        if($v -ge 8 -and $v % 4 -eq 0){ return $v }
        Write-Host "Value must be increments of 4, starting at 8." -ForegroundColor Yellow
    }
}

function Run-INL([string]$argsLine){
    # Wrap launching to show command and run
    Write-Host
    Write-Host ">> inlretro.exe $argsLine"
    & .\inlretro.exe $argsLine.Split(' ')
    if($LASTEXITCODE -ne 0){
        Write-Host "inlretro.exe exited with code $LASTEXITCODE" -ForegroundColor Red
    }
}

while($true){
    Show-Header
    $sys = Select-Console
    $cartridge = Get-CartridgeName

    switch($sys){
        1 {  # NES
            $nesmap = Select-Mapper
            # PRG size (KB), >=8 and multiple of 4
            $prg = Read-KB-MultipleOf4 "What size (in KB) is the PRG ROM?"
            # CHR present?
            $hasChr = Read-YesNo "Does the PCB have a Character (CHR) ROM?"
            $chr = $null
            if($hasChr -eq 'y'){
                $chr = Read-KB-MultipleOf4 "What size (in KB) is the CHR ROM?"
            }
            # WRAM present?
            $hasWram = Read-YesNo "Does the PCB have save data (WRAM)?"

            $destNes = ".\games\$cartridge.nes"
            $sramOut = ".\games\sram\$cartridge.nes"

            # Build argument list matching the original CMD logic
            if($hasChr -eq 'n'){
                if($hasWram -eq 'y'){
                    # No CHR, has WRAM
                    Run-INL "-s scripts/inlretro2.lua -c NES -m $nesmap -x $prg -d `"$destNes`" -a `"$sramOut`" -w 8"
                } else {
                    # No CHR, no WRAM
                    Run-INL "-s scripts/inlretro2.lua -c NES -m $nesmap -x $prg -d `"$destNes`""
                }
            } else {
                if($hasWram -eq 'y'){
                    # Has CHR, has WRAM
                    Run-INL "-s scripts/inlretro2.lua -c NES -m $nesmap -x $prg -y $chr -d `"$destNes`" -a `"$sramOut`" -w 8"
                } else {
                    # Has CHR, no WRAM
                    Run-INL "-s scripts/inlretro2.lua -c NES -m $nesmap -x $prg -y $chr -d `"$destNes`""
                }
            }

            Write-Host
            Write-Host "Starting over to dump the next cartridge."
            Write-Host "You can remove the cartridge at this time."
            Pause-Continue
        }
        2 {  # SNES
            $dest = ".\games\$cartridge.sfc"
            $sram = ".\games\$cartridge.srm"
            Run-INL "-s scripts/inlretro2.lua -c SNES -d `"$dest`" -a `"$sram`""
            Pause-Continue
        }
        3 {  # N64 (placeholder, not implemented in original batch)
            Write-Host "N64 flow is not defined in the original CMD. Add args as needed." -ForegroundColor Yellow
            Pause-Continue
        }
        4 {  # Gameboy / GBA (placeholder)
            Write-Host "Gameboy/GBA flow is not defined in the original CMD. Add args as needed." -ForegroundColor Yellow
            Pause-Continue
        }
        5 {  # Sega Genesis (placeholder)
            Write-Host "Sega Genesis flow is not defined in the original CMD. Add args as needed." -ForegroundColor Yellow
            Pause-Continue
        }
    }
}
