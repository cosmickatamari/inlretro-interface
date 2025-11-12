<#
.SYNOPSIS
    INL Retro Dumper Interface - An interactive cartridge dumping tool.
	
.DESCRIPTION
    Interactive PowerShell interface for dumping retro game cartridges using the INL Retro Dumper hardware. 
	Supports multiple cartridge based systems from the 8 and 16 bit era.

.NOTES
    Author: Cosmic Katamari (@cosmickatamari)
    Twitter/X: @cosmickatamari
    Last Updated: 10/26/2025
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

# Enable strict mode for better error detection
Set-StrictMode -Version Latest

function Read-YesNo {
    param([string]$prompt)
    
    while($true){
        $v = (Read-Host "$prompt (y/n)").Trim().ToLower()
        if($v -eq 'y'){ return $true }
        if($v -eq 'n'){ return $false }
        Write-Host "Please enter Y or N." -ForegroundColor Yellow
    }
}

# PowerShell 7.x check
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Clear-Host
	
	Write-Host "--- WARNING ---" -ForegroundColor Red
	Write-Host "`nThis script requires " -NoNewline -ForegroundColor Yellow
    Write-Host "PowerShell 7.5.3" -NoNewline -ForegroundColor Magenta
    Write-Host " or higher.`nYour current version: " -NoNewline -ForegroundColor Yellow
    Write-Host "$($PSVersionTable.PSVersion)" -NoNewline -ForegroundColor Magenta
	Write-Host "." -NoNewline -ForegroundColor Yellow
    
    if (Read-YesNo "`n`nWould you like to download and install the latest PowerShell version?") {
        Write-Host "`nDownloading and installing PowerShell..." -ForegroundColor Green
        try {
            & winget install --id Microsoft.PowerShell --source winget --silent --accept-package-agreements --accept-source-agreements
            Write-Host "`nPowerShell installation completed!" -ForegroundColor Green
            Write-Host "Please restart your terminal and run again." -ForegroundColor Cyan
        } catch {
            Write-Host "`nFailed to install PowerShell via winget." -ForegroundColor Red
            Write-Host "Please manually download PowerShell from: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Yellow
        }
    } else {
        Write-Host "`nPowerShell upgrade was declined. This script will not otherwise function. `nExiting..." -ForegroundColor Yellow
    }
    exit 1
}

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

function Read-KB-MultipleOf4 {
    param([string]$prompt)
    
    while($true){
        $v = Read-Int $prompt
        if($v -ge 8 -and $v % 4 -eq 0){ return $v }
        Write-Host "Value must be increments of 4, starting with 8." -ForegroundColor Yellow
    }
}

# Global declarations
$BROWSER_OPEN_DELAY_MS = 500      	# Default delay for browser to open.
$BROWSER_NES_DELAY_MS = 750       	# Longer delay for NES database web site.
$TIMESDUMPED = 0					# How many times the program has dumped a cartridge in that session.
$script:SessionStartTime = $null   # Track session start time for timing

# Last dump parameters (for ReDump functionality)
$script:LastArgsArray = $null
$script:LastCartDest = $null
$script:LastSramDest = $null
$script:LastHasSRAM = $false
$script:BaseCartDest = $null  			# Original filename without suffixes
$script:BaseSramDest = $null  			# Original filename without suffixes
$script:BrowserPromptShown = $false  	# Track if already asked about opening browser

# Logging configuration
$LOG_DIR = Join-Path $PSScriptRoot "logs"
$LOG_FILENAME = "interface-cmds-" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + ".txt"
$LOG_FILE = Join-Path $LOG_DIR $LOG_FILENAME

# Add Windows Forms reference for screen dimensions
Add-Type -AssemblyName System.Windows.Forms

# Window positioning helpers - using .NET method
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
    Start-Process "https://github.com/cosmickatamari/inlretro-interface"
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
        
        [bool]$Success = $true,
        
        [string]$DetectionInfo = $null,
        
        [bool]$IsRedump = $false
    )
    
    $timestamp = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
    $cartSizeKB = 0
    $sramSizeKB = 0
    $cartSizeFormatted = "0"
    $sramSizeFormatted = "0"
    
    # Get cartridge file size if it exists
    if (Test-Path $CartridgeFile) {
        $cartSize = (Get-Item $CartridgeFile).Length
        $cartSizeKB = [math]::Round($cartSize / 1KB, 0)
        $cartSizeFormatted = "{0:N0} KB ({1:N0} bytes)" -f $cartSizeKB, $cartSize
    }
    
    # Get SRAM file size if it exists
    if ($SramFile -and (Test-Path $SramFile)) {
        $sramSize = (Get-Item $SramFile).Length
        $sramSizeKB = [math]::Round($sramSize / 1KB, 0)
        $sramSizeFormatted = "{0:N0} KB ({1:N0} bytes)" -f $sramSizeKB, $sramSize
    }
    
    # Format log entry with clean structure
    $commandLine = if ($IsRedump) { $CommandString } else { ".\inlretro.exe $CommandString" }
    $logEntry = @"
Cartridge $script:TIMESDUMPED processed $timestamp
Command: $commandLine
Binary: $CartridgeFile (Size: $cartSizeFormatted)
"@
    
    # Only include SRAM line if SRAM file exists and has content
    if ($SramFile -and (Test-Path $SramFile) -and $sramSizeKB -gt 0) {
        $logEntry += "`nSave RAM: $SramFile (Size: $sramSizeFormatted)"
    }
    
    # Add detection information if provided (with indentation)
    if ($DetectionInfo -and $DetectionInfo.Trim() -ne "") {
        $logEntry += "`nDetection Info:"
        # Split detection info into lines and indent each method
        $detectionLines = $DetectionInfo -split "`n"
        foreach ($line in $detectionLines) {
            if ($line.Trim() -ne "") {
                # Check if this is a section header (Cartridge Info:)
                if ($line -match "^Cartridge Info:$") {
                    $logEntry += "`n$line"
                }
                # Check if this is a method line (starts with "Method") - don't indent method headers
                elseif ($line -match "^Method \d+:") {
                    $logEntry += "`n$line"
                }
                # Check if this is a final status message - don't indent these
                elseif ($line -match "^Final SRAM detection status:" -or $line -match "^SRAM detected.*will dump") {
                    $logEntry += "`n$line"
                } else {
                    # Indent content under methods
                    $logEntry += "`n>> $line"
                }
            } else {
                # Empty line - add as is for spacing
                $logEntry += "`n"
            }
        }
    }
    
    # Add session timing information
    if ($null -ne $script:SessionStartTime) {
        $sessionElapsed = (Get-Date) - $script:SessionStartTime
        $sessionMinutes = [math]::Floor($sessionElapsed.TotalMinutes)
        $sessionSeconds = [math]::Floor($sessionElapsed.TotalSeconds % 60)
        $sessionTimeFormatted = if ($sessionMinutes -gt 0) { 
            "${sessionMinutes}m ${sessionSeconds}s" 
        } else { 
            "${sessionSeconds}s" 
        }
        $logEntry += "`nSession Time: $sessionTimeFormatted"
    }
    
    $logEntry += "`nStatus: $(if($Success) { 'Great Success!' } else { 'Failure.' })"
    $logEntry += "`n`n-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-+-+-+-`n"
    
    # Write to log file
    try {
        Add-Content -Path $LOG_FILE -Value $logEntry -Encoding UTF8
    } catch {
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
}

# UI Display functions, called during main loop.
function Show-Header {
    Clear-Host
    
    # Position window at top-left and expand to full height
    $hwnd = Get-CallerHwnd
    Set-WindowPosition -Hwnd $hwnd
    
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
    Write-Host "Last Released: 10/26/2025"
    Write-Host "Version:       0.10f"
    Write-Host "Log File:      $LOG_FILE"
    Write-Host "`n-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-+-+-+-"
    
    $Host.UI.RawUI.ForegroundColor = 'White'
}

function Select-Console {
    Write-Host "`nSelect A Console:" -ForegroundColor Cyan
    Write-Host "`n 1 - Nintendo Entertainment System" -ForegroundColor White
    Write-Host " 2 - Nintendo Famicom (Family Computer)" -ForegroundColor White
    Write-Host " 3 - Super Nintendo Entertainment System" -ForegroundColor White
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

function ConvertTo-SafeFileName {
    param(
        [Parameter(Mandatory)]
        [string]$FileName
    )
    
    # Replace specific characters with " - " for Windows compatibility
    # Characters: < > : " / \ |
    $safeName = $FileName -replace '[<>:"/\\|]', ' - '
    
    # Remove other invalid characters (strip out ? and *)
    $safeName = $safeName -replace '[?*]', ''
    
    # Trim any extra spaces that might have been created
    $safeName = $safeName -replace '\s+', ' ' -replace '^\s+|\s+$', ''
    
    return $safeName
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

# Core dumping functions, called during cartridge operations.
# Nintendo Entertainment System and Famicom Section (mostly share the same mappers).
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

    Invoke-INLRetro -ArgsArray $argsArray -CartDest $cartDest -SramDest $sramDest -HasSRAM $hasSRAM -CartridgeTitle ""
}

function Invoke-INLRetro {
    param(
        [string[]]$ArgsArray,
        [string]$CartDest,
        [string]$SramDest,
        [bool]$HasSRAM,
        [bool]$IsRedump = $false,
        [string]$CartridgeTitle = "",
        [string]$DetectionInfo = $null
    )

    # Session timing is now set at the beginning of detection process

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

    Write-Host ".\inlretro.exe $pretty" -ForegroundColor DarkCyan
    Write-Host ""

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
            $redumpMessage = "Re-running previous cartridge dump command. Subsequent dump attempts are saved with incrementing identifiers appended to the output file name."
            Write-DumpLog -CommandString $redumpMessage -CartridgeFile $CartDest -SramFile $SramDest -Success $false -DetectionInfo $DetectionInfo
        } else {
            Write-DumpLog -CommandString $pretty -CartridgeFile $CartDest -SramFile $SramDest -Success $false -DetectionInfo $DetectionInfo
        }
    } else {
        $script:TIMESDUMPED++
        
        # Calculate session timing
        $sessionElapsed = (Get-Date) - $script:SessionStartTime
        $sessionMinutes = [math]::Floor($sessionElapsed.TotalMinutes)
        $sessionSeconds = [math]::Floor($sessionElapsed.TotalSeconds % 60)
        $sessionTimeFormatted = if ($sessionMinutes -gt 0) { 
            "${sessionMinutes}m ${sessionSeconds}s" 
        } else { 
            "${sessionSeconds}s" 
        }
        
        Write-Host "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-" -ForegroundColor DarkCyan
        Write-Host "During this session, you have created $script:TIMESDUMPED cartridge dump(s) in $sessionTimeFormatted." -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "Your cartridge dump is located at $CartDest." -ForegroundColor Cyan
        
        # Display cartridge ROM file size
        if (Test-Path $CartDest) {
            $cartSize = (Get-Item $CartDest).Length
            $cartSizeKB = [math]::Round($cartSize / 1KB, 0)
            $cartSizeFormatted = "{0:N0}" -f $cartSize
            $cartSizeKBFormatted = "{0:N0}" -f $cartSizeKB
            Write-Host "ROM file size: $cartSizeKBFormatted KB ($cartSizeFormatted bytes)" -ForegroundColor Cyan
        }
        
        # Check if SRAM file was actually created (Lua script may have determined no SRAM exists)
        if ($HasSRAM -and (Test-Path $SramDest)) {
            Write-Host "Your save data is located at $SramDest." -ForegroundColor Cyan
            
            # Verify the SRAM file was created and show its size for debugging
            if ($true) {
                $sramSize = (Get-Item $SramDest).Length
                $sramSizeKB = [math]::Round($sramSize / 1KB, 0)
                $sramSizeFormatted = "{0:N0}" -f $sramSize
                Write-Host "SRAM file size: $sramSizeKB KB ($sramSizeFormatted bytes)" -ForegroundColor Cyan
                
                # Check if SRAM file size matches expected size
                if ($sramSizeKB -eq 32) {
                    Write-Host "SRAM size (32KB) appears correct for Super Mario World 2: Yoshi's Island" -ForegroundColor Green
                } elseif ($sramSizeKB -eq 64) {
                    Write-Host "Note: 64KB SRAM detected - verify this is correct for your game" -ForegroundColor Yellow
                } elseif ($sramSizeKB -eq 96) {
                    Write-Host "WARNING: 96KB SRAM detected - this is likely the SuperFX expansion RAM, not save data" -ForegroundColor Red
                    Write-Host "For Yoshi's Island, the save data should be 32KB, not 96KB" -ForegroundColor Red
                }
                
                # Check SRAM file content for data integrity
                try {
                    $sramBytes = [System.IO.File]::ReadAllBytes($SramDest)
                    $zeroBytes = ($sramBytes | Where-Object { $_ -eq 0 }).Count
                    $nonZeroBytes = $sramBytes.Count - $zeroBytes
                    $zeroPercentage = [math]::Round(($zeroBytes / $sramBytes.Count) * 100, 1)
                    
                    Write-Host "`nSRAM Content Analysis:" -ForegroundColor Cyan
                    Write-Host "Total bytes: $($sramBytes.Count)" -ForegroundColor White
                    Write-Host "Zero bytes: $zeroBytes ($zeroPercentage%)" -ForegroundColor White
                    Write-Host "Non-zero bytes: $nonZeroBytes" -ForegroundColor White
                    
                    # Show first 16 bytes in hex for debugging
                    $first16Bytes = $sramBytes[0..15] | ForEach-Object { "{0:X2}" -f $_ }
                    Write-Host "First 16 bytes: $($first16Bytes -join ' ')" -ForegroundColor White
                    
                    if ($zeroPercentage -gt 95) {
                        Write-Host "⚠️  WARNING: SRAM file is mostly zeros - this may indicate no save data or corrupted dump" -ForegroundColor Red
                    } elseif ($zeroPercentage -lt 50) {
                        Write-Host "✓ SRAM file contains substantial data - looks good" -ForegroundColor Green
                    } else {
                        Write-Host "ℹ️  SRAM file has mixed data - this is normal for save files and should work with EverDrives and Emulators (such as Mesen)" -ForegroundColor Yellow
                    }
                    
                } catch {
                    Write-Host "Could not analyze SRAM file content: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "Warning: SRAM file was not created at expected location" -ForegroundColor Red
            }
        } elseif ($HasSRAM -and -not (Test-Path $SramDest)) {
            # PowerShell detected SRAM but Lua script determined no SRAM file should be created
            Write-Host "No save data found - the cartridge does not have SRAM or the battery is dead." -ForegroundColor Yellow
            Write-Host "The Lua script correctly determined this cartridge has no usable save RAM." -ForegroundColor Cyan
        }
        
        # Log successful dump
        if ($IsRedump) {
            $redumpMessage = "Re-running previous cartridge dump command. Subsequent dump attempts are saved with incrementing identifiers appended to the output file name."
            Write-DumpLog -CommandString $redumpMessage -CartridgeFile $CartDest -SramFile $SramDest -Success $true -DetectionInfo $DetectionInfo -IsRedump $true
        } else {
            Write-DumpLog -CommandString $pretty -CartridgeFile $CartDest -SramFile $SramDest -Success $true -DetectionInfo $DetectionInfo -IsRedump $false
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
            
            # Set session timer for redump
            $script:SessionStartTime = Get-Date
            
            Invoke-INLRetro -ArgsArray $newArgsArray -CartDest $newCartDest -SramDest $newSramDest -HasSRAM $script:LastHasSRAM -IsRedump $true -CartridgeTitle ""
            
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
            Write-Host "Press [ENTER] to dump another cartridge, or type 'E' to exit: " -ForegroundColor Cyan -NoNewline
            
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
        
        # Convert cartridge name to safe filename
        $safeCartridgeName = ConvertTo-SafeFileName -FileName $cartridge
        
        # Reset browser prompt flag for new cartridge
        $script:BrowserPromptShown = $false
        
        switch($sys){
            'Nintendo Entertainment System' {
                Invoke-NESBasedCartridgeDump -ConsoleFolderName 'nes' -CartridgeName $safeCartridgeName
            }
            
            'Nintendo Famicom (Family Computer)' {
                Invoke-NESBasedCartridgeDump -ConsoleFolderName 'famicom' -CartridgeName $safeCartridgeName
            }
            
            'Super Nintendo Entertainment System' { 
                $gamesRoot = Join-Path $PSScriptRoot 'games\snes'
                $sramRoot = Join-Path $gamesRoot 'sram'
                $cartDest = Join-Path $gamesRoot "$safeCartridgeName.smc"
                $sramDest = Join-Path $sramRoot "$safeCartridgeName.srm"
				$luaScript = Join-Path $PSScriptRoot 'scripts\inlretro2.lua'
				
				[void](New-Item -ItemType Directory -Path $gamesRoot -Force)
                [void](New-Item -ItemType Directory -Path $sramRoot -Force)
                [void](New-Item -ItemType Directory -Path $LOG_DIR -Force)

                
                # Use the same command but capture output to detect SRAM
                $testArgs = @('-s', $luaScript, '-c', 'SNES', '-d', 'NUL', '-a', 'NUL')
                $testExePath = Join-Path $PSScriptRoot 'inlretro.exe'
                
                # Variable to collect detection information for logging
                $detectionMessages = @()
                
                # Start timer for detection process
                $detectionStartTime = Get-Date
                $script:SessionStartTime = Get-Date  # Set session timer at start of detection
                
                try {
                    # Start the detection process as a job
                    $detectionJob = Start-Job -ScriptBlock {
                        param($exePath, $jobArgs)
                        & $exePath @jobArgs 2>&1 | Out-String
                    } -ArgumentList $testExePath, $testArgs
                    
                    # Show progress while job is running with single line updates
                    $counter = 0

                    Write-Host ""
                   
                    while ($detectionJob.State -eq "Running") {
                        $elapsed = (Get-Date) - $detectionStartTime
                        $seconds = [math]::Floor($elapsed.TotalSeconds)
                        if ($seconds -gt $counter) {
                            $counter = $seconds
                            # Update the same line with progress counter
                            Write-Host "`rDetecting cartridge configuration... ($seconds seconds)" -NoNewline -BackgroundColor Black -ForegroundColor DarkCyan
                        }
                        Start-Sleep -Milliseconds 100
                    }
                    
                    # Get the result
                    $headerOutput = Receive-Job $detectionJob
                    Remove-Job $detectionJob
                    
                    # Show completion on same line
                    $detectionElapsed = (Get-Date) - $detectionStartTime
                    $detectionSeconds = [math]::Floor($detectionElapsed.TotalSeconds)
                    Write-Host "`rDetecting cartridge configuration - completed in $detectionSeconds seconds" -ForegroundColor DarkCyan
                    Write-Host ""  # Add line break after detection completion
                    $hasSRAM = $false
                    $sramSizeKB = 0
                    
                    # Method 1: Check initial header - look for "SRAM Size:" followed by anything other than "None"
                    $method1Msg = "Method 1: Checking header for SRAM Size"
                    Write-Host $method1Msg -ForegroundColor Cyan
                    $detectionMessages += $method1Msg
                    
                    if ($headerOutput -match "SRAM Size:\s*(?!None\b).+") {
                        $hasSRAM = $true
                        # Try to extract size from header if specified (ex. "SRAM Size: 32K")
                        if ($headerOutput -match "SRAM Size:\s*(\d+)K") {
                            $sramSizeKB = [int]$matches[1]
                            $method1FoundMsg = "Found SRAM Size in header: $sramSizeKB KB."
                            Write-Host $method1FoundMsg -ForegroundColor Green
                            $detectionMessages += $method1FoundMsg
                        } else {
                            $method1FoundMsg = "Found SRAM Size in header (size not specified)."
                            Write-Host $method1FoundMsg -ForegroundColor Green
                            $detectionMessages += $method1FoundMsg
                        }
                    } else {
                        $method1NoFoundMsg = "No SRAM Size found in header"
                        Write-Host $method1NoFoundMsg -ForegroundColor Yellow
                        $detectionMessages += $method1NoFoundMsg
                    }
                    
                    Write-Host ""  # Add blank line after Method 1
                    $detectionMessages += ""  # Add blank line to log as well
                    
                    # Method 2: Check for detection process finding save RAM and extract size
                    # Look for "Save RAM Size not provided, X kilobytes detected" or similar patterns
                    $method2Msg = "Method 2: Checking for 'Save RAM Size'"
                    Write-Host $method2Msg -ForegroundColor Cyan
                    $detectionMessages += $method2Msg
                    
                    if ($headerOutput -match "Save RAM Size.*?(\d+)\s*kilobytes?\s*detected") {
                        $detectedSizeKB = [int]$matches[1]
                        
                        # Only set hasSRAM if the detected size is greater than 0
                        if ($detectedSizeKB -gt 0) {
                            $foundMsg = "Found Save RAM Size detection message with size: $detectedSizeKB KB."
                            Write-Host $foundMsg -ForegroundColor Green
                            $detectionMessages += $foundMsg
                            
                            $setMsg = "Detected size > 0, setting hasSRAM = true."
                            Write-Host $setMsg -ForegroundColor Green
                            $detectionMessages += $setMsg
                            $hasSRAM = $true
                            $sramSizeKB = $detectedSizeKB
                        } else {
                            $noRamMsg = "No Save RAM detected (size = 0 KB)"
                            Write-Host $noRamMsg -ForegroundColor Yellow
                            $detectionMessages += $noRamMsg
                            $hasSRAM = $false
                            $sramSizeKB = 0
                        }
                    } else {
                        $noDetectMsg = "No 'Save RAM Size' detection message found"
                        Write-Host $noDetectMsg -ForegroundColor Yellow
                        $detectionMessages += $noDetectMsg
                    }
                    
                    # Also check for "kilobits" - need to convert to kilobytes
                    if ($headerOutput -match "SRAM Size:\s*(\d+)\s*kilobits?") {
                        $detectedSizeKbits = [int]$matches[1]
                        $detectedSizeKB = [math]::Ceiling($detectedSizeKbits / 8)  # Convert kilobits to KB
                        
                        if ($detectedSizeKB -gt 0) {
                            $foundKbitsMsg = "Found SRAM Size in kilobits: ${detectedSizeKbits} kilobits = $detectedSizeKB KB"
                            Write-Host $foundKbitsMsg -ForegroundColor Green
                            $detectionMessages += $foundKbitsMsg
                            
                            $hasSRAM = $true
                            $sramSizeKB = $detectedSizeKB
                        }
                    }
                    
                    Write-Host ""  # Add blank line after Method 2
                    $detectionMessages += ""  # Add blank line to log as well
                    
                    # Special case for Donkey Kong Country: Check if Lua script applied the correction
                    # This must be checked FIRST to override any other detection
                    if ($headerOutput -match "Donkey Kong Country detected: Header shows 16 kilobits but PCB indicates 16KB - correcting to 16KB") {
                        $hasSRAM = $true
                        $sramSizeKB = 16
                        $dkcCorrectionMsg = "Donkey Kong Country SRAM size correction applied by Lua script: 16KB"
                        Write-Host $dkcCorrectionMsg -ForegroundColor Green
                        $detectionMessages += $dkcCorrectionMsg
                    }
                    # Special case for Yoshi's Island: Check if Lua script applied the correction
                    elseif ($headerOutput -match "Super Mario World 2: Yoshi's Island detected - Super FX game with Save RAM") {
                        $hasSRAM = $true
                        $sramSizeKB = 32
                        $yoshiCorrectionMsg = "Yoshi's Island SRAM size correction applied by Lua script: 32KB"
                        Write-Host $yoshiCorrectionMsg -ForegroundColor Green
                        $detectionMessages += $yoshiCorrectionMsg
                    }
                    # Fallback for Yoshi's Island if Lua script doesn't detect it
                    elseif ($headerOutput -match "Rom Title:\s*YOSHI'S ISLAND" -and $headerOutput -match "Hardware Type:.*SuperFX.*Save RAM") {
                        $hasSRAM = $true
                        $sramSizeKB = 32
                        $yoshiFallbackMsg = "Yoshi's Island detected via PowerShell fallback: 32KB"
                        Write-Host $yoshiFallbackMsg -ForegroundColor Green
                        $detectionMessages += $yoshiFallbackMsg
                    }
                    # Also check for the "Using SRAM table size" message which shows the final corrected size
                    # This should now show the corrected size after Donkey Kong Country fix
                    if ($headerOutput -match "Using SRAM table size: (\d+) KB") {
                        $correctedSize = [int]$matches[1]
                        if ($correctedSize -gt 0) {
                            $hasSRAM = $true
                            $sramSizeKB = $correctedSize
                            $sramTableMsg = "SRAM table size detected: $correctedSize KB"
                            Write-Host $sramTableMsg -ForegroundColor Green
                            $detectionMessages += $sramTableMsg
                        }
                    }
                    # Check for explicit SRAM size in header (e.g., "SRAM Size: 32K")
                    # Only if no other corrections were applied
                    elseif ($headerOutput -match "SRAM Size:\s*(\d+)K") {
                        $hasSRAM = $true
                        $sramSizeKB = [int]$matches[1]
                    }
                    
                    # Step 3: Check Hardware Type for "Save RAM" indication
                    $method3Msg = "Step 3: Checking Hardware Type for Save RAM"
                    Write-Host $method3Msg -ForegroundColor Cyan
                    $detectionMessages += $method3Msg
                    
                    if ($headerOutput -match "Hardware Type:.*Save RAM") {
                        $foundSaveRamMsg = "Found 'Save RAM' in Hardware Type."
                        Write-Host $foundSaveRamMsg -ForegroundColor Green
                        $detectionMessages += $foundSaveRamMsg
                        
                        # Set hasSRAM if not already set and size is 0 (meaning we need to auto-detect)
                        if (-not $hasSRAM -and $sramSizeKB -eq 0) {
                            $hwTypeMsg = "Hardware Type indicates Save RAM - setting hasSRAM = true, size will be auto-detected."
                            Write-Host $hwTypeMsg -ForegroundColor Green
                            $detectionMessages += $hwTypeMsg
                            $hasSRAM = $true
                            $sramSizeKB = 8  # Default to 8KB if size can't be determined
                        } elseif ($hasSRAM) {
                            $hwTypeMsg = "Hardware Type confirms Save RAM capability (size already determined: ${sramSizeKB}KB)."
                            Write-Host $hwTypeMsg -ForegroundColor Cyan
                            $detectionMessages += $hwTypeMsg
                        }
                    } else {
                        $noSaveRamMsg = "No 'Save RAM' found in Hardware Type."
                        Write-Host $noSaveRamMsg -ForegroundColor Yellow
                        $detectionMessages += $noSaveRamMsg
                    }
                    
                    Write-Host ""  # Add blank line after Step 3
                    $detectionMessages += ""  # Add blank line to log as well
                    
                    # Step 4: Check for Super FX games with SRAM size in Expansion RAM Size field
                    # According to SNES documentation: Super FX games store SRAM size in Expansion RAM Size field
                    # BUT: Skip this for Yoshi's Island which has special handling
                    if (-not ($headerOutput -match "Rom Title:\s*YOSHI'S ISLAND")) {
                        if ($headerOutput -match "Hardware Type:.*SuperFX.*Save RAM" -and $headerOutput -match "SRAM Size:\s*None") {
                            $method4Msg = "Step 4: Checking for SuperFX + Save RAM + SRAM Size None"
                            Write-Host $method4Msg -ForegroundColor Cyan
                            $detectionMessages += $method4Msg
                            $foundSuperFxMsg = "Found SuperFX with Save RAM and SRAM Size None."
                            Write-Host $foundSuperFxMsg -ForegroundColor Green
                            $detectionMessages += $foundSuperFxMsg
                            
                            $checkExpMsg = "Super FX game detected with Save RAM - checking Expansion RAM Size field."
                            Write-Host $checkExpMsg -ForegroundColor Cyan
                            $detectionMessages += $checkExpMsg
                            
                            if ($headerOutput -match "Expansion RAM Size:\s*(\d+)\s*kilobits") {
                                $expRamKBits = [int]$matches[1]
                                $foundExpMsg = "Found Expansion RAM: ${expRamKBits} kilobits."
                                Write-Host $foundExpMsg -ForegroundColor Cyan
                                $detectionMessages += $foundExpMsg
                                
                                # Convert kilobits to KB (1 << exp) * 8 kilobits, converted to KB by dividing by 8
                                # For known values like 512 kilobits: log2(512/8) = log2(64) = 6, so KB = 2^6 = 64
                                $expRamKB = [math]::Round($expRamKBits / 8)
                                $convertMsg = "Converted: ${expRamKBits} kilobits = $expRamKB KB."
                                Write-Host $convertMsg -ForegroundColor Cyan
                                $detectionMessages += $convertMsg
                                
                                # For Super FX games, this expansion RAM size IS the SRAM size
                                $hasSRAM = $true
                                $superFxDetectedMsg = "Super FX SRAM detected via Expansion RAM field: ${expRamKBits} kilobits = ${expRamKB}KB."
                                Write-Host $superFxDetectedMsg -ForegroundColor Green
                                $detectionMessages += $superFxDetectedMsg
                                
                                $sramSizeKB = $expRamKB
                            }
                        } else {
                            $noSuperFxMsg = "Conditions not met for SuperFX detection."
                            Write-Host $noSuperFxMsg -ForegroundColor Yellow
                            $detectionMessages += $noSuperFxMsg
                        }
                    } else {
                        $skipSuperFxMsg = "Skipping SuperFX expansion RAM detection for Yoshi's Island (using 32KB instead)"
                        Write-Host $skipSuperFxMsg -ForegroundColor Cyan
                        $detectionMessages += $skipSuperFxMsg
                    }
                    
                    Write-Host ""  # Add blank line after Step 4
                    $detectionMessages += ""  # Add blank line to log as well
                    
                    # Final status output
                    $finalStatusMsg = "Final SRAM detection status: hasSRAM=$hasSRAM, sramSizeKB=$sramSizeKB"
                    Write-Host $finalStatusMsg -ForegroundColor Cyan
                    $detectionMessages += $finalStatusMsg
                    
                    if ($hasSRAM -and $sramSizeKB -gt 0) {
                        $sramDetectedMsg = "SRAM detected (${sramSizeKB}KB) - will dump save data."
                        Write-Host $sramDetectedMsg -ForegroundColor Green
                        $detectionMessages += $sramDetectedMsg
                    } else {
                        # Ensure hasSRAM is false if size is 0
                        $hasSRAM = $false
                    }
                } catch {
                    # Clean up job if it exists
                    if ($detectionJob) {
                        try {
                            Stop-Job $detectionJob -ErrorAction SilentlyContinue
                            Remove-Job $detectionJob -ErrorAction SilentlyContinue
                        } catch { }
                    }
                    
                    Write-Warning "Could not detect SRAM configuration, assuming no SRAM."
                    $hasSRAM = $false
                    $sramSizeKB = 0
                }
                
                # Fallback for SA-1 games when header parsing fails
                # SA-1 games use BW-RAM for save data, typically 32KB
                if (-not $hasSRAM -and ($headerOutput -match "Could not parse internal ROM header")) {
                    $headerFailedMsg = "Header parsing failed - checking for SA-1 hardware fallback"
                    Write-Host $headerFailedMsg -ForegroundColor Yellow
                    $detectionMessages += $headerFailedMsg
                    
                    # Check if this might be an SA-1 game based on hardware detection
                    # SA-1 games typically have 32KB save RAM
                    $applyFallbackMsg = "Applying SA-1 fallback for failed header parsing"
                    Write-Host $applyFallbackMsg -ForegroundColor Cyan
                    $detectionMessages += $applyFallbackMsg
                    
                    $hasSRAM = $true
                    $sramSizeKB = 32
                    $sa1FallbackMsg = "SA-1 fallback: Setting SRAM to 32KB for failed header parsing."
                    Write-Host $sa1FallbackMsg -ForegroundColor Green
                    $detectionMessages += $sa1FallbackMsg
                }
                
                Write-Host ""  # Add blank line after fallback section
                $detectionMessages += ""  # Add blank line to log as well
                
                # Extract cartridge title from header output for better post-dump verification
                $cartTitle = ""
                if ($headerOutput -match "Rom Title:\s*(.+?)(?:\r?\n|$)") {
                    $cartTitle = $matches[1].Trim()
                }
                
        # Prepare detection information for logging (match screen format with proper spacing)
        $detectionInfo = "`n" + ($detectionMessages -join "`n")
        
        # Add cartridge information to the log
        $cartridgeInfo = @()
        if ($headerOutput -match "Rom Title:\s*(.+?)(?:\r?\n|$)") {
            $cartridgeInfo += "Rom Title:              " + $matches[1].Trim()
        }
        if ($headerOutput -match "Map Mode:\s*(.+?)(?:\r?\n|$)") {
            $cartridgeInfo += "Map Mode:               " + $matches[1].Trim()
        }
        if ($headerOutput -match "Hardware Type:\s*(.+?)(?:\r?\n|$)") {
            $cartridgeInfo += "Hardware Type:          " + $matches[1].Trim()
        }
        if ($headerOutput -match "Rom Size Upper Bound:\s*(.+?)(?:\r?\n|$)") {
            $cartridgeInfo += "Rom Size Upper Bound:   " + $matches[1].Trim()
        }
        if ($headerOutput -match "SRAM Size:\s*(.+?)(?:\r?\n|$)") {
            $cartridgeInfo += "SRAM Size:              " + $matches[1].Trim()
        }
        if ($headerOutput -match "Expansion RAM Size:\s*(.+?)(?:\r?\n|$)") {
            $cartridgeInfo += "Expansion RAM Size:     " + $matches[1].Trim()
        }
        if ($headerOutput -match "Destination Code:\s*(.+?)(?:\r?\n|$)") {
            $cartridgeInfo += "Destination Code:       " + $matches[1].Trim()
        }
        if ($headerOutput -match "Developer:\s*(.+?)(?:\r?\n|$)") {
            $cartridgeInfo += "Developer:              " + $matches[1].Trim()
        }
        if ($headerOutput -match "Version:\s*(.+?)(?:\r?\n|$)") {
            $cartridgeInfo += "Version:                " + $matches[1].Trim()
        }
        if ($headerOutput -match "Checksum:\s*(.+?)(?:\r?\n|$)") {
            $cartridgeInfo += "Checksum:               " + $matches[1].Trim()
        }
        
        # Add cartridge info to detection info
        if ($cartridgeInfo.Count -gt 0) {
            $detectionInfo += "`nCartridge Info:"
            $detectionInfo += "`n" + ($cartridgeInfo -join "`n")
            $detectionInfo += "`n"  # Add blank line after checksum
        }
        
        # Build complete arguments for both ROM and SRAM in single process
        $argsArray = @('-s', $luaScript, '-c', 'SNES', '-d', $cartDest)
        
        if ($hasSRAM -and $sramSizeKB -gt 0) {
            $argsArray += @('-a', $sramDest, '-w', "$sramSizeKB")
            Write-Host "Argument call used (game ROM and save data):" -ForegroundColor Cyan
        } else {
            Write-Host "Argument call used (Only game ROM, no Save Data detected):" -ForegroundColor Cyan
        }

        Invoke-INLRetro -ArgsArray $argsArray -CartDest $cartDest -SramDest $sramDest -HasSRAM $hasSRAM -CartridgeTitle $cartTitle -DetectionInfo $detectionInfo
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
        Write-Host "`nExiting application..." -ForegroundColor Cyan
        exit 1
    }
}