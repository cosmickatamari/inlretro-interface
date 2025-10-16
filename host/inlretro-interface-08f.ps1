<#
.SYNOPSIS
    INL Retro Dumper Interface - An interactive cartridge dumping tool.
	
.DESCRIPTION
    Interactive PowerShell interface for dumping retro game cartridges using the INL Retro Dumper hardware. 
	Supports multiple cartridge based systems from the 8 and 16 bit era.

.NOTES
    Author: Cosmic Katamari (@cosmickatamari)
    Twitter/X: @cosmickatamari
    Last Updated: 10/15/2025
    Requires: PowerShell 7.x or higher

.LINKS
    GitHub Project: https://github.com/cosmickatamari/INL-retro-progdump
	Original Author's Project: https://gitlab.com/InfiniteNesLives/INL-retro-progdump
	Cart dumper purchase link: https://www.infiniteneslives.com/inlretro.php
	3D printed case purchase link: (need to upload)
	3D printed case can self-printed link: https://www.printables.com/model/2808-inlretro-dumper-programmer-case-v2
	
#>

[CmdletBinding()]
param()

# User interaction input validations
function Read-Int {
    param(
        [string]$prompt, 
        [int]$minValue = [int]::MinValue, 
        [int]$maxValue = [int]::MaxValue
    )
    
    while($true){
        $raw = Read-Host $prompt
        $result = 0
        if([int]::TryParse($raw, [ref]$result) -and $result -ge $minValue -and $result -le $maxValue){
            return $result
        }
        Write-Host "Please enter a valid number between $minValue and $maxValue." -ForegroundColor Yellow
    }
}

function Read-YesNo {
    param([string]$prompt)
    
    while($true){
        $v = (Read-Host "$prompt (y/n)").Trim().ToLower()
        if($v -eq 'y'){ return $true }
        if($v -eq 'n'){ return $false }
        Write-Host "Please enter Y or N." -ForegroundColor Yellow
    }
}

function Read-KB-MultipleOf4 {
    param([string]$prompt)
    
    while($true){
        $v = Read-Int $prompt
        if($v -ge 8 -and $v % 4 -eq 0){ return $v }
        Write-Host "Value must be increments of 4, starting with 8." -ForegroundColor Yellow
    }
}

# PowerShell 7.x check
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7.5.3 or higher." -ForegroundColor Red
    Write-Host "Your current version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host ""
    
    if (Read-YesNo "Would you like to download and install the latest PowerShell version?") {
        Write-Host "`nDownloading and installing PowerShell..." -ForegroundColor Green
        try {
            & winget install --id Microsoft.PowerShell --source winget --silent --accept-package-agreements --accept-source-agreements
            Write-Host "`nPowerShell installation completed!" -ForegroundColor Green
            Write-Host "Please restart your terminal and run this script again." -ForegroundColor Cyan
        } catch {
            Write-Host "`nFailed to install PowerShell via winget." -ForegroundColor Red
            Write-Host "Please manually download PowerShell from: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Yellow
        }
    } else {
        Write-Host "`nPowerShell upgrade declined. Exiting..." -ForegroundColor Yellow
    }
    exit 1
}

# Enable strict mode for better error detection
Set-StrictMode -Version Latest

# Global declarations
$BROWSER_OPEN_DELAY_MS = 500      	# Default delay for browser to open.
$BROWSER_NES_DELAY_MS = 750       	# Longer delay for NES database lookup.
$TIMESDUMPED = 0					# How many times the program has dumped a cartridge in that session.

# Last dump parameters (for ReDump functionality)
$script:LastArgsArray = $null
$script:LastCartDest = $null
$script:LastSramDest = $null
$script:LastHasSRAM = $false
$script:BaseCartDest = $null  # Original filename without suffixes
$script:BaseSramDest = $null  # Original filename without suffixes
$script:BrowserPromptShown = $false  # Track if we've already asked about opening browser

# Logging configuration
$LOG_DIR = Join-Path $PSScriptRoot "logs"
$LOG_FILENAME = "interface-cmds-" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + ".txt"
$LOG_FILE = Join-Path $LOG_DIR $LOG_FILENAME

# Add Windows Forms reference for screen dimensions
Add-Type -AssemblyName System.Windows.Forms

# Window positioning helpers - using .NET methods directly
function Get-CallerHwnd {
    $h = [System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle
    if ($h -and $h -ne [IntPtr]::Zero) { return $h }
    return [IntPtr]::Zero
}

function Set-WindowPosition {
    param([IntPtr]$Hwnd)
    
    try {
        # Get screen dimensions
        $screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height
        
        # Use PowerShell's RawUI for both resizing and positioning
        $console = $Host.UI.RawUI
        $maxRows = [Math]::Floor($screenHeight / 16) - 2
        
        # Get current buffer size to respect limits
        $currentBuffer = $console.BufferSize
        $maxWidth = $currentBuffer.Width
        $maxHeight = [Math]::Max($currentBuffer.Height, $maxRows)
        
        # Set buffer size first (must be set before window size)
        $console.BufferSize = New-Object System.Management.Automation.Host.Size($maxWidth, $maxHeight)
        
        # Set window size (cannot exceed buffer size)
        $console.WindowSize = New-Object System.Management.Automation.Host.Size($maxWidth, $maxRows)
        
        # Try to set window position to top-left
        try {
            $console.WindowPosition = New-Object System.Management.Automation.Host.Coordinates(0, 0)
        } catch {
            # Console positioning not supported in this host
        }
        
        # Additional positioning attempt using Win32 API
        try {
            $code = @'
using System;
using System.Runtime.InteropServices;
public class WindowPos {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
}
'@
            Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
            
            if ("WindowPos" -as [type]) {
                $hwnd = [WindowPos]::GetForegroundWindow()
                if ($hwnd -ne [IntPtr]::Zero) {
                    [void][WindowPos]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x0001 -bor 0x0004 -bor 0x0040)
                }
            }
        } catch {
            # Silently continue if this method also fails
        }
        
    } catch {
        Write-Warning "Window positioning error: $($_.Exception.Message)"
    }
}

# Initialize data directory
$dataDir = Join-Path $PSScriptRoot "data"
[void](New-Item -ItemType Directory -Path $dataDir -Force)

# Load external data files
try {
    $NESmapperMenu = Get-Content (Join-Path $dataDir "nes-mappers.json") -ErrorAction Stop | ConvertFrom-Json
    $consoleMap = Get-Content (Join-Path $dataDir "consoles.json") -ErrorAction Stop | ConvertFrom-Json
    Write-Host "Configuration and data files loaded successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to load required data files from $dataDir"
    Write-Error "Please ensure the following files exist:"
    Write-Error "  - nes-mappers.json"
    Write-Error "  - consoles.json" 
	Write-Error "`n The latest release can be downloaded at: https://github.com/cosmickatamari/inlretro-interface"
    Write-Error "`nError details: $($_.Exception.Message)"
    exit 1
}

function Open-UrlInDefaultBrowser-AndReturn {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$DelayMs = $BROWSER_OPEN_DELAY_MS
    )

    # Open URL in default browser
    Start-Process $Url

    # Wait for browser to load
    Start-Sleep -Milliseconds $DelayMs
}

# Log file creation
function Write-DumpLog {
    param(
        [Parameter(Mandatory)]
        [string]$CommandString,
        
        [Parameter(Mandatory)]
        [string]$CartridgeFile,
        
        [string]$SramFile = $null,
        
        [bool]$Success = $true
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $cartSizeKB = 0
    $sramSizeKB = 0
    
    # Get cartridge file size if it exists
    if (Test-Path $CartridgeFile) {
        $cartSizeKB = [math]::Round((Get-Item $CartridgeFile).Length / 1KB, 2)
    }
    
    # Get SRAM file size if it exists
    if ($SramFile -and (Test-Path $SramFile)) {
        $sramSizeKB = [math]::Round((Get-Item $SramFile).Length / 1KB, 2)
    }
    
    # Format log entry based on whether it's a redump or not
    if ($CommandString.StartsWith("Reexecuting")) {
        # Redump - no quotes, no exe name
        $logEntry = @"
[$timestamp] Dump #$script:TIMESDUMPED - Command: $CommandString
[$timestamp] Dump #$script:TIMESDUMPED - Cartridge: $CartridgeFile (Size: $cartSizeKB KB)
"@
        
        # Only include SRAM line if SRAM file exists and has content
        if ($SramFile -and (Test-Path $SramFile) -and $sramSizeKB -gt 0) {
            $logEntry += "`n[$timestamp] Dump #$script:TIMESDUMPED - SRAM: $SramFile (Size: $sramSizeKB KB)"
        }
    } else {
        # Regular dump - quoted command with exe name, unquoted filenames
        $logEntry = @"
[$timestamp] Dump #$script:TIMESDUMPED - Command: ".\inlretro.exe $CommandString"
[$timestamp] Dump #$script:TIMESDUMPED - Cartridge: $CartridgeFile (Size: $cartSizeKB KB)
"@
        
        # Only include SRAM line if SRAM file exists and has content
        if ($SramFile -and (Test-Path $SramFile) -and $sramSizeKB -gt 0) {
            $logEntry += "`n[$timestamp] Dump #$script:TIMESDUMPED - SRAM: $SramFile (Size: $sramSizeKB KB)"
        }
    }
    
    $logEntry += "`n[$timestamp] Dump #$script:TIMESDUMPED - Status: $(if($Success) { 'SUCCESS' } else { 'FAILED' })"
    $logEntry += "`n" + ("-" * 80) + "`n"
    
    # Write to log file
    try {
        Add-Content -Path $LOG_FILE -Value $logEntry -Encoding UTF8
    } catch {
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
}

# UI Display funcitons
# Called during main loop
function Show-Header {
    Clear-Host
    
    # Position window at top-left and expand to full height
    $hwnd = Get-CallerHwnd
    Set-WindowPosition -Hwnd $hwnd
    
    # ASCII art lines with gradient colors (5 lines total)
    $asciiLines = @(
        "  __  _   _  _       ____      _                __        _             __                ",
        " |__|| \ | || |     |  _ \ ___| |_ ____ ___    |__| ____ | |_ ___ ____ / _| ____  ___ ___ ",
        "  || |  \| || |     | |_) / _ \ __|  __/ _ \    || |  _ \| __/ _ \  __| |_ / _  |/ __/ _ \",
        "  || | |\  || |___  |  _ <  __/ |_| | | (_) |   || | | | | |_| __/ |  |  _| (_| | (_|  __/",
        " |__||_| \_||_____| |_| \_\___|\__|_|  \___/   |__||_| |_|\__\___|_|  |_|  \____|\___\___|"
    )
    
    # Display ASCII art with gradient
    $gradientColors = @('Cyan', 'Cyan', 'DarkGreen', 'DarkGreen', 'Blue')
    
    for ($i = 0; $i -lt $asciiLines.Count; $i++) {
        $color = $gradientColors[$i]
        Write-Host $asciiLines[$i] -ForegroundColor $color
    }
    
    $Host.UI.RawUI.ForegroundColor = 'DarkCyan'
    
    Write-Host "`n`nCreated By:    Cosmic Katamari"
    Write-Host "Twitter/X:     @cosmickatamari"
    Write-Host "Last Released: 10/15/2025"
    Write-Host "Version:       0.8f"
    Write-Host "Log File:      $LOG_FILE"
    Write-Host "`n-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-+-+-+-"
    
    $Host.UI.RawUI.ForegroundColor = 'White'
}

function Select-Console {
    Write-Host "`nSelect A Console:" -ForegroundColor Cyan
    Write-Host "`n 1 - Nintendo Entertainment System" -ForegroundColor White
    Write-Host " 2 - Nintendo Famicom (Family Computer)" -ForegroundColor White
    Write-Host " 3 - Super Nintendo Entertainment System" -ForegroundColor Yellow
    Write-Host " 4 - Nintendo 64" -ForegroundColor DarkGray
    Write-Host " 5 - Gameboy / Gameboy Advance" -ForegroundColor DarkGray
    Write-Host " 6 - Sega Genesis" -ForegroundColor DarkGray
    Write-Host " E - Exit" -ForegroundColor Yellow
    Write-Host
    
    while ($true) {
        $choice = Read-Host "Choice"
        
        # Check for exit command
        if ($choice -match '^[eE]$') {
            Write-Host "`nExiting INL Retro Interface. Goodbye!" -ForegroundColor DarkCyan
            exit 0
        }
        
        # Check for valid number
        $numChoice = 0
        if ([int]::TryParse($choice, [ref]$numChoice) -and $numChoice -ge 1 -and $numChoice -le 6) {
            return $consoleMap.($numChoice.ToString())
        }
        
        Write-Host "Please enter a number between 1-6, or 'E' to exit." -ForegroundColor Yellow
    }
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
    Write-Host "`nFor quicker access to important information, the NES/Famicom database has opened to the search results from the game title.`n" -ForegroundColor Blue

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
    
    Write-Host "`nFor AxROM cartridges, select the BNROM mapper." -ForegroundColor Cyan
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

# Core dumping functions
# Called during cartridge operations
# Nintendo Entertainment System and Famicom Section (mostly share the same mappers)
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
    [void](New-Item -ItemType Directory -Path $LOG_DIR -Force)

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
        [bool]$HasSRAM,
        [bool]$IsRedump = $false
    )

    $exePath = Join-Path $PSScriptRoot 'inlretro.exe'
    
    # Check if executable exists
    if (-not (Test-Path $exePath)) {
        Write-Error "inlretro.exe not found at $exePath"
        return
    }
	
    # Save parameters for potential ReDump
    $script:LastArgsArray = $ArgsArray
    $script:LastCartDest = $CartDest
    $script:LastSramDest = $SramDest
    $script:LastHasSRAM = $HasSRAM
    
    # Save base filenames only if this is the first dump (no suffix in the name)
    if ($CartDest -notmatch '-dump\d+\.[^.]+$') {
        $script:BaseCartDest = $CartDest
        $script:BaseSramDest = $SramDest
    }

    $pretty = (
        $ArgsArray | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"','`"') + '"' } else { $_ }
        }
    ) -join ' '

    Write-Host "`nProgram and argument call used: .\inlretro.exe $pretty" -ForegroundColor Blue

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
        
        # Log failed attempt
        if ($IsRedump) {
            $redumpMessage = "Reexecuting previous cartridge dump command. Subsequent dump iterations are appended with incremental identifiers in the output file name."
            Write-DumpLog -CommandString $redumpMessage -CartridgeFile $CartDest -SramFile $SramDest -Success $false
        } else {
            Write-DumpLog -CommandString $pretty -CartridgeFile $CartDest -SramFile $SramDest -Success $false
        }
    } else {
        $script:TIMESDUMPED++
        Write-Host "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-" -ForegroundColor Green
        Write-Host "During this session, you have created $script:TIMESDUMPED cartridge dump(s)." -ForegroundColor Green
        Write-Host "`Your cartridge dump is located at $CartDest." -ForegroundColor Green
        
        if ($HasSRAM) {
            Write-Host "Your save data is located at $SramDest." -ForegroundColor Green
            Write-Host "It will work with EverDrives and Emulators (such as Mesen)." -ForegroundColor Green
        }
        
        # Log successful dump
        if ($IsRedump) {
            $redumpMessage = "Reexecuting previous cartridge dump command. Subsequent dump iterations are appended with incremental identifiers in the output file name."
            Write-DumpLog -CommandString $redumpMessage -CartridgeFile $CartDest -SramFile $SramDest -Success $true
        } else {
            Write-DumpLog -CommandString $pretty -CartridgeFile $CartDest -SramFile $SramDest -Success $true
        }
    }
}

function ReDump {
    # Check if parameters from a previous dump exist
    if ($null -eq $script:LastArgsArray) {
        return  # No previous dump to redo
    }

    # Redumping will continue until the choice is 'n'
    while ($true) {
        Write-Host "`nIf your newly dumped ROM isn't working correctly, double check that the cartridge is clean."
        $rerun = Read-YesNo "An incremental version will be made, proceed with another attempt?"
        
        if($rerun) {
            $suffix = "-dump$script:TIMESDUMPED"
            
            # Use the BASE filenames (without any existing suffixes)
            $newCartDest = $script:BaseCartDest -replace '(\.[^.]+)$', "$suffix`$1"
            $newSramDest = $script:BaseSramDest -replace '(\.[^.]+)$', "$suffix`$1"
            
            # Modify the file paths in the args array
            $newArgsArray = $script:LastArgsArray.Clone()
            for ($i = 0; $i -lt $newArgsArray.Count; $i++) {
                if ($newArgsArray[$i] -eq '-d' -and $i + 1 -lt $newArgsArray.Count) {
                    $newArgsArray[$i + 1] = $newCartDest
                }
                if ($newArgsArray[$i] -eq '-a' -and $i + 1 -lt $newArgsArray.Count) {
                    $newArgsArray[$i + 1] = $newSramDest
                }
            }
            
            Invoke-INLRetro -ArgsArray $newArgsArray -CartDest $newCartDest -SramDest $newSramDest -HasSRAM $script:LastHasSRAM -IsRedump $true
            
            # Display cleaning instructions with option to open URL (only first time)
            if (-not $script:BrowserPromptShown) {
                Write-Host "`nStill having issues? A good cleaning can often fix read errors." -ForegroundColor Cyan
                Write-Host "--- DO NOT USE BRASSO! ---" -ForegroundColor Red
                Write-Host "`nAlso, reseating the cartridge will sometimes yield better results."
                
                $openLink = Read-YesNo "Would you like to access the RetroRGB.com article on cleaning best practices?"
                if ($openLink) {
                    Open-UrlInDefaultBrowser-AndReturn -Url "https://www.retrorgb.com/cleangames.html"
                }
            
                $script:BrowserPromptShown = $true
            }
        
        } else {
            Write-Host "`nIt is now safe to remove the cartridge." -ForegroundColor Cyan
            Write-Host "Press [ENTER] to dump another cartridge, or type 'E' to exit." -ForegroundColor Cyan
            
            $exitChoice = Read-Host
            if ($exitChoice -match '^[eE]$') {
                Write-Host "`nExiting INL Retro Dumper Interface. Goodbye!" -ForegroundColor DarkCyan
                exit 0
            }
            break
        }
    }
}

# Main Dumping Execution
while($true){
    try {
        Show-Header
        $sys = Select-Console
        $cartridge = Get-CartridgeName -ConsoleName $sys
        
        # Reset browser prompt flag for new cartridge
        $script:BrowserPromptShown = $false
        
        switch($sys){
            'Nintendo Entertainment System' {
                Invoke-NESBasedCartridgeDump -ConsoleFolderName 'nes' -CartridgeName $cartridge
            }
            
            'Nintendo Famicom (Family Computer)' {
                Invoke-NESBasedCartridgeDump -ConsoleFolderName 'famicom' -CartridgeName $cartridge
            }
            
            'Super Nintendo Entertainment System' { 
                $gamesRoot = Join-Path $PSScriptRoot 'games\snes'
                $sramRoot = Join-Path $gamesRoot 'sram'
                $cartDest = Join-Path $gamesRoot "$cartridge.sfc"
                $sramDest = Join-Path $sramRoot "$cartridge.srm"
                
                # Create directories on-demand
                [void](New-Item -ItemType Directory -Path $gamesRoot -Force)
                [void](New-Item -ItemType Directory -Path $sramRoot -Force)
                [void](New-Item -ItemType Directory -Path $LOG_DIR -Force)
                
                $luaScript = Join-Path $PSScriptRoot 'scripts\inlretro2.lua'
                $argsArray = @('-s', $luaScript, '-c', 'SNES', '-d', $cartDest, '-a', $sramDest)
                Invoke-INLRetro -ArgsArray $argsArray -CartDest $cartDest -SramDest $sramDest -HasSRAM $true
            }
            'Nintendo 64' {  # N64 (placeholder)
                Write-Host "Add args as needed." -ForegroundColor Yellow
                Read-Host
            }
            'Gameboy / Gameboy Advance' {  # Gameboy / GBA (placeholder)
                Write-Host "Add args as needed." -ForegroundColor Yellow
                Read-Host
            }
            'Sega Genesis' {  # Sega Genesis (placeholder)
                Write-Host "Add args as needed." -ForegroundColor Yellow
                Read-Host
            }
        }
        ReDump
        
    } catch {
        Write-Host "`n`nAn error occurred during operation:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "`nStack Trace:" -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
        Write-Host "`nPress [ENTER] to restart the application..." -ForegroundColor Cyan
        Read-Host
    }
}