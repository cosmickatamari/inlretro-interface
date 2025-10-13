<#
.SYNOPSIS
    INL Retro Dumper Interface - Interactive cartridge dumping tool

.DESCRIPTION
    Interactive PowerShell interface for dumping retro game cartridges using 
    the INL Retro Dumper hardware. Supports NES, Famicom, SNES, N64, 
    Gameboy/GBA, and Sega Genesis cartridges.

.NOTES
    Author: Cosmic Katamari (@cosmickatamari)
    Twitter/X: @cosmickatamari
    Last Updated: 10/12/2025
    Requires: PowerShell 7.x or higher

.LINK
    https://github.com/cosmickatamari/INL-retro-progdump
#>

[CmdletBinding()]
param()

# PowerShell 7.x check
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7 or higher." -ForegroundColor Red
    exit 1
}

# Enable strict mode for better error detection
Set-StrictMode -Version Latest

# -------- Configuration Constants --------------------------------------------
$BROWSER_OPEN_DELAY_MS = 500      # Default delay for browser to open
$BROWSER_NES_DELAY_MS = 750       # Longer delay for NES database lookup
$FOCUS_RESTORE_ATTEMPTS = 3       # Number of times to retry window focus
$FOCUS_RETRY_DELAY_MS = 100       # Delay between focus retry attempts
# ----------------------------------------------------------------------------

# -------- Focus helpers (no resize, fast) -----------------------------------
if (-not ("Win32FocusForce" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class Win32FocusForce {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    public const int SW_RESTORE = 9;
}
"@
}

function Get-CallerHwnd {
    $h = [System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle
    if ($h -and $h -ne [IntPtr]::Zero) { return $h }
    return [Win32FocusForce]::GetForegroundWindow()
}

function Restore-WindowForce {
    param([IntPtr]$Hwnd)
    if (-not $Hwnd -or $Hwnd -eq [IntPtr]::Zero) { return }

    # Only restore if minimized; don't change size otherwise
    if ([Win32FocusForce]::IsIconic($Hwnd)) {
        [void][Win32FocusForce]::ShowWindow($Hwnd, [Win32FocusForce]::SW_RESTORE)
    }

    # Bypass foreground lock so focus actually returns
    $fg = [Win32FocusForce]::GetForegroundWindow()
    $curThread = [Win32FocusForce]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
    $tgtThread = [Win32FocusForce]::GetWindowThreadProcessId($Hwnd, [IntPtr]::Zero)
    if ($curThread -ne 0 -and $tgtThread -ne 0 -and $curThread -ne $tgtThread) {
        [void][Win32FocusForce]::AttachThreadInput($curThread, $tgtThread, $true)
        [void][Win32FocusForce]::BringWindowToTop($Hwnd)
        [void][Win32FocusForce]::SetForegroundWindow($Hwnd)
        [void][Win32FocusForce]::AttachThreadInput($curThread, $tgtThread, $false)
    } else {
        [void][Win32FocusForce]::BringWindowToTop($Hwnd)
        [void][Win32FocusForce]::SetForegroundWindow($Hwnd)
    }
}
# ----------------------------------------------------------------------------

# Minimal helper to open URL in default browser and return focus
function Open-UrlInDefaultBrowser-AndReturn {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$DelayMs = $BROWSER_OPEN_DELAY_MS
    )

    $prevHwnd = Get-CallerHwnd

    # Open URL in default browser
    Start-Process $Url

    # Wait for browser to load and steal focus
    Start-Sleep -Milliseconds $DelayMs
    
    # Force focus back with multiple attempts
    for ($i = 0; $i -lt $FOCUS_RESTORE_ATTEMPTS; $i++) {
        Restore-WindowForce -Hwnd $prevHwnd
        Start-Sleep -Milliseconds $FOCUS_RETRY_DELAY_MS
    }
}

# Initialize data directory and load external data files
$dataDir = Join-Path $PSScriptRoot "data"
[void](New-Item -ItemType Directory -Path $dataDir -Force)

# Load external data files - required for script operation
try {
    $NESmapperMenu = Get-Content (Join-Path $dataDir "nes-mappers.json") -ErrorAction Stop | ConvertFrom-Json
    $consoleMap = Get-Content (Join-Path $dataDir "consoles.json") -ErrorAction Stop | ConvertFrom-Json
    $config = Get-Content (Join-Path $dataDir "config.json") -ErrorAction Stop | ConvertFrom-Json
    Write-Host "Configuration and data files loaded successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to load required data files from $dataDir"
    Write-Error "Please ensure the following files exist:"
    Write-Error "  - nes-mappers.json"
    Write-Error "  - consoles.json" 
    Write-Error "  - config.json"
    Write-Error "Error details: $($_.Exception.Message)"
    exit 1
}

# Note: Directories are created on-demand when dumping cartridges

function Read-Int([string]$prompt, [int]$minValue = [int]::MinValue, [int]$maxValue = [int]::MaxValue){
    while($true){
        $raw = Read-Host $prompt
        $result = 0
        if([int]::TryParse($raw, [ref]$result) -and $result -ge $minValue -and $result -le $maxValue){
            return $result
        }
        Write-Host "Please enter a valid number between $minValue and $maxValue." -ForegroundColor Yellow
    }
}

function Read-YesNo([string]$prompt){
    while($true){
        $v = (Read-Host "$prompt (y/n)").Trim().ToLower()
        if($v -eq 'y'){ return $true }
        if($v -eq 'n'){ return $false }
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

function Wait-ForUserInput {
    Read-Host
}

function Show-Header {
    Clear-Host
    $Host.UI.RawUI.ForegroundColor = 'DarkCyan'

    Write-Host "  __  _   _  _       ____      _               ____                                 "
    Write-Host " |__|| \ | || |     |  _ \ ___| |_ ____ ___   |  _ \ _   _ ________  ____   ___ ___ "
    Write-Host "  || |  \| || |     | |_) / _ \ __|  __/ _ \  | | | | | | |  _   _ \|  _ \ / _ \ __|"
    Write-Host "  || | |\  || |___  |  _ <  __/ |_| | | (_) | | |_| | |_| | | | | | | |_) |  __/ |  "
    Write-Host " |__||_| \_||_____| |_| \_\___|\__|_|  \___/  |____/ \____|_| |_| |_|  __/ \___|_|  "
    Write-Host "  __        _             __                                        | |"
    Write-Host " |__| ____ | |_ ___ ____ / _| ____  ___ ___ "
    Write-Host "  || |  _ \| __/ _ \  __| |_ / _  |/ __/ _ \"
    Write-Host "  || | | | | |_| __/ |  |  _| (_| | (_|  __/"
    Write-Host " |__||_| |_|\__\___|_|  |_|  \____|\___\___|"
    
    Write-Host "`n Created By:    $($config.author)"
    Write-Host " Twitter/X:     $($config.twitter)"
    Write-Host "`n Last Released: $($config.releaseDate)"
    Write-Host " Version:       $($config.version)"
    Write-Host "`n-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-"
    
    $Host.UI.RawUI.ForegroundColor = 'White'
}

function Select-Console {
    Write-Host "`n`nSelect A Console" -ForegroundColor Blue
    Write-Host
    Write-Host " 1 - Nintendo Entertainment System" -ForegroundColor White
    Write-Host " 2 - Nintendo Famicom (Family Computer)" -ForegroundColor White
    Write-Host " 3 - Super Nintendo Entertainment System" -ForegroundColor Yellow
    Write-Host " 4 - Nintendo 64" -ForegroundColor DarkGray
    Write-Host " 5 - Gameboy / Gameboy Advance" -ForegroundColor DarkGray
    Write-Host " 6 - Sega Genesis" -ForegroundColor DarkGray
    Write-Host
    
    $choice = Read-Int "Selection" -minValue 1 -maxValue 6
    return $consoleMap.($choice.ToString())
}

function Get-CartridgeName {
    param(
        [Parameter(Mandatory)]
        [string]$ConsoleName
    )
    
    while($true){
        $name = Read-Host "`nWhat is the name of your $ConsoleName game?"
        if([string]::IsNullOrWhiteSpace($name)){ continue }
        return $name.Trim()
    }
}

function Select-Mapper {
    param(
        [Parameter(Mandatory)]
        [string]$CartridgeName
    )
    
    $baseurl = "https://nescartdb.com/search/basic?keywords="
    $endurl  = "&kwtype=game"
    $encoded = [uri]::EscapeDataString($CartridgeName)
    $url     = $baseurl + $encoded + $endurl

    # Open default browser and return focus to the script
    Open-UrlInDefaultBrowser-AndReturn -Url $url -DelayMs $BROWSER_NES_DELAY_MS

    Show-Header
    Write-Host "`nFor quicker access, the NES database has opened to the search results from the game title." -ForegroundColor Blue

    $columns = 5

    # Find the widest entry (number + name) so padding fits
    $maxLen = (0..($NESmapperMenu.Count - 1) | ForEach-Object {
        $num = ($_ + 1).ToString("00")
        (" {0}. {1}" -f $num, $NESmapperMenu[$_]).Length
    } | Measure-Object -Maximum).Maximum
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
    
    Write-Host "`n"
    Write-Host "For AxROM cartridges, select the BNROM mapper." -ForegroundColor Cyan
    Write-Host "For MHROM cartridges, select the GxROM mapper." -ForegroundColor Cyan
    Write-Host "For MMC6 cartridges, select the MMC3 mapper." -ForegroundColor Cyan
    
    while ($true) {
        $ans = Read-Int "`nMapper Number"
        if ($ans -ge 1 -and $ans -le $NESmapperMenu.Count) {
            return $NESmapperMenu[$ans-1]
        }
        Write-Host ("Please choose between 1-{0}." -f $NESmapperMenu.Count) -ForegroundColor Yellow
    }
}

function Invoke-NESBasedCartridgeDump {
    param(
        [Parameter(Mandatory)]
        [string]$ConsoleFolderName,
        
        [Parameter(Mandatory)]
        [string]$CartridgeName
    )
    
    $nesmap = Select-Mapper -CartridgeName $CartridgeName
    $prg    = Read-KB-MultipleOf4 "`nWhat is the size (in KB) of the Program (PRG) ROM? (typically PRG0)"
    $hasChr = Read-YesNo "`nDoes the cartridge have a Character (CHR) ROM? (typically CHR0)"
    $chr    = $null
    
    if ($hasChr) { 
        $chr = Read-KB-MultipleOf4 "What is the size (in KB) of the Character ROM?" 
    }

    $hasSRAM = Read-YesNo "`nDoes the cartridge contain a battery save (Working RAM)?"

    # Paths for storing files
    $gamesRoot = Join-Path $PSScriptRoot "games\$ConsoleFolderName"
    $sramRoot = Join-Path $gamesRoot 'sram'
    $cartDest  = Join-Path $gamesRoot "$CartridgeName.nes"
    $sramDest  = Join-Path $sramRoot "$CartridgeName.sav"
    
    # Create directories on-demand
    [void](New-Item -ItemType Directory -Path $gamesRoot -Force)
    [void](New-Item -ItemType Directory -Path $sramRoot -Force)

    # Arguments passed to the executable
    $argsArray = @(
        '-s', (Join-Path $PSScriptRoot 'scripts\inlretro2.lua')
        '-c', 'NES'
        '-m', "$nesmap"
        '-x', "$prg"
    )

    if ($hasChr) { 
        $argsArray += @('-y', "$chr") 
    }
        
    $argsArray += @('-d', "$cartDest")
        
    if ($hasSRAM) { 
        $argsArray += @('-a', "$sramDest", '-w', '8') 
    }

    Invoke-INLRetro -ArgsArray $argsArray -CartDest $cartDest -SramDest $sramDest -HasSRAM $hasSRAM
}

function Invoke-INLRetro {
    param(
        [string[]]$ArgsArray,
        [string]$CartDest,
        [string]$SramDest,
        [bool]$HasSRAM
    )

    $exePath = Join-Path $PSScriptRoot 'inlretro.exe'
    
    # Check if executable exists
    if (-not (Test-Path $exePath)) {
        Write-Error "inlretro.exe not found at $exePath"
        return
    }

    $pretty = (
        $ArgsArray | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"','`"') + '"' } else { $_ }
        }
    ) -join ' '

    Write-Host "`nProgram and argument call used:" -ForegroundColor Blue
    Write-Host ".\inlretro.exe $pretty" -ForegroundColor Blue
    
    # Initialize exit code for strict mode safety
    $exitCode = 0
    
    try {
        & $exePath @ArgsArray
        $exitCode = $LASTEXITCODE
    } catch {
        Write-Error "Failed to execute inlretro.exe: $($_.Exception.Message)"
        $exitCode = -1
    }
    
    Write-Host

    if ($exitCode -ne 0) {
        Write-Host "inlretro.exe exited with code $exitCode." -ForegroundColor Red
        Write-Host "`nThe cartridge could not be dumped." -ForegroundColor Red
    } else {
        Write-Host "`nYour cartridge dump is located at $CartDest." -ForegroundColor Green
        
        if ($HasSRAM) {
            Write-Host "Your save data is located at $SramDest." -ForegroundColor Green
            Write-Host "It will work with EverDrives and Emulators (such as Mesen)." -ForegroundColor Green
        }
        
        Write-Host "`nIt is safe to remove the cartridge." -ForegroundColor Cyan
        Write-Host "Pressing [ENTER] will restart the application, allowing for the next cartridge to be dumped." -ForegroundColor Cyan
    }
    
    Wait-ForUserInput
}

# -------------------------------- Main Loop ---------------------------------
while($true){
    try {
        Show-Header
        $sys = Select-Console
        $cartridge = Get-CartridgeName -ConsoleName $sys
        
        switch($sys){
            'Nintendo Entertainment System' {
                Invoke-NESBasedCartridgeDump -ConsoleFolderName 'nes' -CartridgeName $cartridge
            }
            
            'Nintendo Famicom (Family Computer)' {
                Invoke-NESBasedCartridgeDump -ConsoleFolderName 'famicom' -CartridgeName $cartridge
            }
            
            'Super Nintendo Entertainment System' {  # SNES
                $gamesRoot = Join-Path $PSScriptRoot 'games\snes'
                $sramRoot = Join-Path $gamesRoot 'sram'
                $cartDest = Join-Path $gamesRoot "$cartridge.sfc"
                $sramDest = Join-Path $sramRoot "$cartridge.srm"
                
                # Create directories on-demand
                [void](New-Item -ItemType Directory -Path $gamesRoot -Force)
                [void](New-Item -ItemType Directory -Path $sramRoot -Force)
                
                $luaScript = Join-Path $PSScriptRoot 'scripts\inlretro2.lua'
                $argsArray = @('-s', $luaScript, '-c', 'SNES', '-d', $cartDest, '-a', $sramDest)
                Invoke-INLRetro -ArgsArray $argsArray -CartDest $cartDest -SramDest $sramDest -HasSRAM $true
            }
            'Nintendo 64' {  # N64 (placeholder)
                Write-Host "Add args as needed." -ForegroundColor Yellow
                Wait-ForUserInput
            }
            'Gameboy / Gameboy Advance' {  # Gameboy / GBA (placeholder)
                Write-Host "Add args as needed." -ForegroundColor Yellow
                Wait-ForUserInput
            }
            'Sega Genesis' {  # Sega Genesis (placeholder)
                Write-Host "Add args as needed." -ForegroundColor Yellow
                Wait-ForUserInput
            }
        }
    } catch {
        Write-Host "`n`nAn error occurred during operation:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "`nStack Trace:" -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
        Write-Host "`nPress [ENTER] to restart the application..." -ForegroundColor Cyan
        Read-Host
    }
}
