<#
.SYNOPSIS
	INL Retro Dumper Interface - An interactive cartridge dumping tool.
	
.DESCRIPTION
	Interactive PowerShell interface for dumping retro game cartridges using the INL Retro Dumper hardware. 
	Supports multiple cartridge based systems from the 8 and 16 bit era.

.NOTES
	Author: Cosmic Katamari (@cosmickatamari)
	Twitter/X: @cosmickatamari
	Last Updated: 11/11/2025
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

# Constants

# Timing constants (milliseconds)
$script:BROWSER_OPEN_DELAY_MS = 500
$script:BROWSER_NES_DELAY_MS = 750

# SRAM size constants (KB)
$script:SUPERFX_SRAM_SIZE_KB = 32
$script:DEFAULT_SRAM_SIZE_KB = 8

# File signature display length
$script:SIGNATURE_BYTES = 16

# Progress display constants
$script:DETECTION_PROGRESS_INTERVAL_MS = 100
$script:COMPLETION_MSG_PAD_LENGTH = 80


# Global Variables

# Session tracking
$script:TIMESDUMPED = 0
$script:SessionStartTime = $null

# Last dump parameters (for ReDump functionality)
$script:LastArgsArray = $null
$script:LastCartDest = $null
$script:LastSramDest = $null
$script:LastHasSRAM = $false
$script:BaseCartDest = $null
$script:BaseSramDest = $null
$script:BrowserPromptShown = $false

# Logging configuration
$script:LOG_DIR = Join-Path $PSScriptRoot "logs"
$script:LOG_FILENAME = "inl-interface-" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + ".txt"
$script:LOG_FILE = Join-Path $script:LOG_DIR $script:LOG_FILENAME


# Utility Functions

<#
.SYNOPSIS
	Reads yes/no input from user with validation
.DESCRIPTION
	Prompts user and validates input, defaulting to 'n'
#>
function Read-YesNo {
	param([string]$prompt)
	
	while ($true) {
		$v = (Read-Host "$prompt (y/n, default: n)").Trim().ToLower()
		if ($v -eq '') { return $false }
		if ($v -eq 'y') { return $true }
		if ($v -eq 'n') { return $false }
		Write-Host "Please enter Y or N (or press [ENTER] for default: N)." -ForegroundColor Yellow
	}
}

<#
.SYNOPSIS
	Reads integer input from user with range validation
#>
function Read-Int {
	param(
		[string]$prompt, 
		[int]$minValue = [int]::MinValue, 
		[int]$maxValue = [int]::MaxValue
	)
	
	while ($true) {
		$raw = Read-Host $prompt
		$result = 0
		if ([int]::TryParse($raw, [ref]$result) -and $result -ge $minValue -and $result -le $maxValue) {
			return $result
		}
		Write-Host "Please enter a valid number between $minValue and $maxValue." -ForegroundColor Yellow
	}
}

<#
.SYNOPSIS
	Reads KB value that is a multiple of 4, starting from 8
#>
function Read-KB-MultipleOf4 {
	param([string]$prompt)
	
	while ($true) {
		$v = Read-Int $prompt
		if ($v -ge 8 -and $v % 4 -eq 0) { return $v }
		Write-Host "Value must be increments of 4, starting with 8." -ForegroundColor Yellow
	}
}

<#
.SYNOPSIS
	Formats elapsed time as human-readable string
#>
function Format-SessionTime {
	param([DateTime]$StartTime)
	
	if ($null -eq $StartTime) { return "" }
	
	$elapsed = (Get-Date) - $StartTime
	$minutes = [math]::Floor($elapsed.TotalMinutes)
	$seconds = [math]::Floor($elapsed.TotalSeconds % 60)
	
	if ($minutes -gt 0) {
		return "${minutes}m ${seconds}s"
	}
	return "${seconds}s"
}

<#
.SYNOPSIS
	Extracts cartridge information from header output
#>
function Get-CartridgeInfo {
	param([string]$HeaderOutput)
	
	$cartridgeInfo = @()
	# Use ordered array to preserve field order (matches console output order)
	$fieldOrder = @(
		"Rom Title",
		"Map Mode",
		"Hardware Type",
		"Rom Size Upper Bound",
		"SRAM Size",
		"Expansion RAM Size",
		"Destination Code",
		"Developer",
		"Version",
		"Checksum"
	)
	
	$fieldPatterns = @{
		"Rom Title" = "Rom Title:\s*(.+?)(?:\r?\n|$)"
		"Map Mode" = "Map Mode:\s*(.+?)(?:\r?\n|$)"
		"Hardware Type" = "Hardware Type:\s*(.+?)(?:\r?\n|$)"
		"Rom Size Upper Bound" = "Rom Size Upper Bound:\s*(.+?)(?:\r?\n|$)"
		"SRAM Size" = "SRAM Size:\s*(.+?)(?:\r?\n|$)"
		"Expansion RAM Size" = "Expansion RAM Size:\s*(.+?)(?:\r?\n|$)"
		"Destination Code" = "Destination Code:\s*(.+?)(?:\r?\n|$)"
		"Developer" = "Developer:\s*(.+?)(?:\r?\n|$)"
		"Version" = "Version:\s*(.+?)(?:\r?\n|$)"
		"Checksum" = "Checksum:\s*(.+?)(?:\r?\n|$)"
	}
	
	# Iterate in specified order to match console output
	foreach ($fieldName in $fieldOrder) {
		if ($fieldPatterns.ContainsKey($fieldName)) {
			$pattern = $fieldPatterns[$fieldName]
			if ($HeaderOutput -match $pattern) {
				$value = $matches[1].Trim()
				$paddedName = $fieldName.PadRight(23)
				$cartridgeInfo += "$paddedName $value"
			}
		}
	}
	
	# Fallback for failed header parsing
	if ($cartridgeInfo.Count -eq 0 -and $HeaderOutput -match "Could not parse internal ROM header") {
		$fallbackInfo = @()
		
		if ($HeaderOutput -match "(?:^|\n)\s*Map Mode:\s+(0x[\dA-Fa-f]+|\w+)") {
			$fallbackInfo += "Map Mode:               " + $matches[1]
		}
		if ($HeaderOutput -match "(?:^|\n)\s*ROM Type:\s+(0x[\dA-Fa-f]+)") {
			$fallbackInfo += "ROM Type:               " + $matches[1]
		}
		if ($HeaderOutput -match "(?:^|\n)\s*ROM Size:\s+(0x[\dA-Fa-f]+)") {
			$fallbackInfo += "ROM Size:               " + $matches[1]
		}
		if ($HeaderOutput -match "firmware app ver request:\s+(\d+\.\d+\.\w+)") {
			$fallbackInfo += "Version:                " + $matches[1]
		} elseif ($HeaderOutput -match "Device firmware version:\s+(\d+\.\d+\.\w+)") {
			$fallbackInfo += "Version:                " + $matches[1]
		}
		
		if ($fallbackInfo.Count -gt 0) {
			$cartridgeInfo = $fallbackInfo
		}
	}
	
	return $cartridgeInfo
}

<#
.SYNOPSIS
	Analyzes file content and returns analysis as text
#>
function Get-FileAnalysisText {
	param(
		[Parameter(Mandatory)]
		[string]$FilePath,
		
		[Parameter(Mandatory)]
		[string]$FileType  # "ROM" or "SRAM"
	)
	
	$analysisText = @()
	
	if (-not (Test-Path $FilePath)) {
		return $analysisText
	}
	
	try {
		$fileSize = (Get-Item $FilePath).Length
		$fileSizeKB = [math]::Round($fileSize / 1KB, 0)
		$fileSizeFormatted = "{0:N0}" -f $fileSize
		$fileSizeKBFormatted = "{0:N0}" -f $fileSizeKB
		
		# Use "Game ROM" instead of just "ROM" for the label
		$typeLabel = if ($FileType -eq "ROM") { "Game ROM" } else { $FileType }
		$analysisText += "$typeLabel file size: $fileSizeKBFormatted KB ($fileSizeFormatted bytes)"
		
		$fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
		
		# Calculate leading zeros (only for ROM)
		$leadingZeros = 0
		if ($FileType -eq "ROM") {
			for ($i = 0; $i -lt $fileBytes.Length; $i++) {
				if ($fileBytes[$i] -eq 0) {
					$leadingZeros++
				} else {
					break
				}
			}
		}
		
		# Calculate zero/non-zero bytes
		$zeroBytes = ($fileBytes | Where-Object { $_ -eq 0 }).Count
		$nonZeroBytes = $fileBytes.Length - $zeroBytes
		$zeroPercentage = [math]::Round(($zeroBytes / $fileBytes.Length) * 100, 1)
		$usedPercentage = [math]::Round(($nonZeroBytes / $fileBytes.Length) * 100, 1)
		
		# Show space usage
		$analysisText += "Used space: {0:N0} bytes ({1}%)" -f $nonZeroBytes, $usedPercentage
		$analysisText += "Free space: {0:N0} bytes ({1}%)" -f $zeroBytes, $zeroPercentage
		if ($FileType -eq "SRAM" -and $zeroBytes -eq $fileBytes.Length) {
			$analysisText += "Warning: All bytes are zero; SRAM appears empty or mapping failed."
		}
		
		# Show file signature
		if ($fileBytes.Length -ge $script:SIGNATURE_BYTES) {
			$signature = $fileBytes[0..($script:SIGNATURE_BYTES - 1)] | ForEach-Object { "{0:X2}" -f $_ }
			$analysisText += "File Signature: $($signature -join ' ')"
			
			if ($FileType -eq "SRAM") {
				$nonZeroSignatureBytes = $signature | Where-Object { $_ -ne '00' }
				if ($null -eq $nonZeroSignatureBytes -or $nonZeroSignatureBytes.Count -eq 0) {
					$analysisText += ""
					$analysisText += "The SRAM file signature contains only values of '00'."
					$analysisText += "Please confirm that the Used Space field above shows valid data."
					$analysisText += "If it does not, the SRAM may not have been captured correctly."
				}
			}
		}
		
		# Show leading padding warning (ROM only)
		if ($FileType -eq "ROM" -and $leadingZeros -gt 0) {
			$analysisText += ""
			$analysisText += "Leading padding detected: $leadingZeros bytes of zeros at start of file."
			$analysisText += "First non-zero byte at offset $leadingZeros / 0x$($leadingZeros.ToString('X'))."
			$analysisText += "Note: This padding may be intentional for certain cartridge boards."
		}
	} catch {
		if ($FileType -eq "SRAM") {
			$analysisText += "Could not analyze SRAM file content: $($_.Exception.Message)"
		}
		# Silently continue for ROM analysis
	}
	
	return $analysisText
}

<#
.SYNOPSIS
	Analyzes file content and displays usage statistics
#>
function Show-FileAnalysis {
	param(
		[Parameter(Mandatory)]
		[string]$FilePath,
		
		[Parameter(Mandatory)]
		[string]$FileType  # "ROM" or "SRAM"
	)
	
	if (-not (Test-Path $FilePath)) {
		return
	}
	
	$analysisText = Get-FileAnalysisText -FilePath $FilePath -FileType $FileType
	
	foreach ($line in $analysisText) {
		$trimmedLine = $line.TrimStart()
		
		if ($line -match "^(Game ROM|SRAM) file size:") {
			$parts = $line -split ":", 2
			Write-Host ($parts[0] + ": ") -NoNewline -ForegroundColor Cyan
			if ($parts.Count -eq 2) {
				Write-Host $parts[1].Trim() -ForegroundColor Magenta
			}
		} elseif ($line -match "^Used space:|^Free space:|^File Signature:") {
			$parts = $line -split ":", 2
			Write-Host ($parts[0] + ": ") -NoNewline -ForegroundColor Cyan
			if ($parts.Count -eq 2) {
				Write-Host $parts[1].Trim() -ForegroundColor Magenta
			}
		} elseif ($trimmedLine -match "^(Leading padding|First non-zero|Note:|The SRAM file signature contains only values of '00'\.|Please confirm that the Used Space field above shows valid data\.|If it does not, the SRAM may not have been captured correctly\.)") {
			Write-Host $line -ForegroundColor DarkYellow
		} elseif ($line -eq "") {
			Write-Host ""
		} elseif ($line -match "^Could not analyze") {
			Write-Host $line -ForegroundColor Yellow
		} else {
			Write-Host $line
		}
	}
}


# PowerShell Version Check

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


# Window Management

# Add Windows Forms reference for screen dimensions
Add-Type -AssemblyName System.Windows.Forms

<#
.SYNOPSIS
	Gets the current process window handle
#>
function Get-CallerHwnd {
	$h = [System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle
	if ($h -and $h -ne [IntPtr]::Zero) { return $h }
	return [IntPtr]::Zero
}

<#
.SYNOPSIS
	Sets window position and size for optimal display
#>
function Set-WindowPosition {
	param([IntPtr]$Hwnd)
	
	try {
		# Get screen dimensions
		$screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height
		
		# Use PowerShell's RawUI for resizing and positioning
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


# Data File Loading

# Initialize data directory
$dataDir = Join-Path $PSScriptRoot "data"
[void](New-Item -ItemType Directory -Path $dataDir -Force)

# Load external data files
try {
	$script:NESmapperMenu = Get-Content (Join-Path $dataDir "nes-mappers.json") -ErrorAction Stop | ConvertFrom-Json
	$script:consoleMap = Get-Content (Join-Path $dataDir "consoles.json") -ErrorAction Stop | ConvertFrom-Json
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


# Browser Functions

<#
.SYNOPSIS
	Opens URL in default browser and waits
#>
function Open-UrlInDefaultBrowser-AndReturn {
	param(
		[Parameter(Mandatory)][string]$Url,
		[int]$DelayMs = $script:BROWSER_OPEN_DELAY_MS
	)

	# Open URL in default browser
	Start-Process $Url

	# Wait for browser to load
	Start-Sleep -Milliseconds $DelayMs
}


# Logging Functions

<#
.SYNOPSIS
	Writes dump operation information to log file
#>
function Write-DumpLog {
	param(
		[Parameter(Mandatory)]
		[string]$CommandString,
		
		[Parameter(Mandatory)]
		[string]$CartridgeFile,
		
		[string]$SramFile = $null,
		
		[bool]$Success = $true,
		
		[string]$DetectionInfo = $null,
		
		[bool]$IsRedump = $false,
		
		[string]$CartridgeTitle = "",
		
		[string]$ProcessSummary = $null
	)
	
	$timestamp = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
	
	# Format log entry with clean structure
	$commandLine = if ($IsRedump) { 
		"A redump of the game cartridge was performed using the original parameters. Subsequent dump attempts are saved with incrementing identifiers appended to the output file name." 
	} else { 
		".\inlretro.exe $CommandString" 
	}
	
	# Add cartridge name to the processed message if available
	$cartridgeNameText = if ($CartridgeTitle -and $CartridgeTitle.Trim() -ne "") { " ($CartridgeTitle)" } else { "" }
	$redumpText = if ($IsRedump) { " (redump)" } else { "" }
	
	$logEntry = @"
====[ Cartridge $script:TIMESDUMPED$redumpText$cartridgeNameText processed $timestamp ]====

Parameters used:
$commandLine

"@
	
	# Add detection information if provided (with indentation)
	if ($DetectionInfo -and $DetectionInfo.Trim() -ne "") {
		$logEntry += "`nDetection Info:"
		$detectionLines = $DetectionInfo -split "`n"
		$isFirstStep = $true
		$inCartridgeInfoSection = $false
		$cartridgeInfoComplete = $false
		
		foreach ($line in $detectionLines) {
			if ($line.Trim() -ne "") {
				# Check if this is a section header (Cartridge Info:)
				if ($line -match "^Cartridge Info:$") {
					$inCartridgeInfoSection = $true
					# Ensure single line break before Cartridge Info (not double)
					# Check if logEntry ends with newline to avoid double spacing
					if ($logEntry -match "`n$") {
						$logEntry += "$line"
					} else {
						$logEntry += "`n$line"
					}
				}
				# If we're in Cartridge Info section, add lines without indentation
				elseif ($inCartridgeInfoSection) {
					$logEntry += "`n$line"
					# Check if this is the last line of cartridge info (next iteration will process Process Summary)
				}
				# Check if this is a step line (starts with "Step") - don't indent step headers
				elseif ($line -match "^Step \d+:") {
					if ($isFirstStep) {
						$logEntry += "$line"
						$isFirstStep = $false
					} else {
						$logEntry += "`n$line"
					}
				}
				# Check if this is a final status message - don't indent these
				elseif ($line -match "^Final SRAM detection status:" -or $line -match "^SRAM detected.*will dump") {
					$logEntry += "`n$line"
				} else {
					# Indent content under steps
					$logEntry += "`n>> $line"
				}
			} else {
				# Empty line - check if we just finished Cartridge Info section
				if ($inCartridgeInfoSection -and -not $cartridgeInfoComplete) {
					$cartridgeInfoComplete = $true
					# Insert Process Summary right after Cartridge Info section (no header)
					# Add blank line before Process Summary (before game ROM location)
					if ($ProcessSummary -and $ProcessSummary.Trim() -ne "") {
						$logEntry += "`n"  # Blank line after cartridge info
						$processSummaryLines = $ProcessSummary -split "`n"
						foreach ($summaryLine in $processSummaryLines) {
							$logEntry += "`n$summaryLine"
						}
					}
				}
				$logEntry += "`n"
			}
		}
		
		# If Cartridge Info section was processed but we didn't hit an empty line, add Process Summary now
		if ($inCartridgeInfoSection -and -not $cartridgeInfoComplete) {
			# Insert Process Summary right after Cartridge Info section (no header)
			# Add blank line before Process Summary (before game ROM location)
			if ($ProcessSummary -and $ProcessSummary.Trim() -ne "") {
				$logEntry += "`n"  # Blank line after cartridge info
				$processSummaryLines = $ProcessSummary -split "`n"
				foreach ($summaryLine in $processSummaryLines) {
					$logEntry += "`n$summaryLine"
				}
			}
		}
	} else {
		# No detection info, but we might still have Process Summary (no header)
		if ($ProcessSummary -and $ProcessSummary.Trim() -ne "") {
			$processSummaryLines = $ProcessSummary -split "`n"
			foreach ($summaryLine in $processSummaryLines) {
				$logEntry += "`n$summaryLine"
			}
		}
	}
	
	# Add session timing information
	$sessionTimeFormatted = Format-SessionTime -StartTime $script:SessionStartTime
	if ($sessionTimeFormatted -ne "") {
		$logEntry += "`nSession Time: $sessionTimeFormatted"
	}
	
	$logEntry += "`nStatus: $(if($Success) { 'Great Success!' } else { 'Failure.' })"
	# Separator with dashes (same length as original -+-+ pattern: 89 characters)
	$separator = "-" * 89
	$logEntry += "`n`n$separator`n"
	
	# Write to log file efficiently
	try {
		$logEntry | Out-File -FilePath $script:LOG_FILE -Append -Encoding UTF8
	} catch {
		Write-Warning "Failed to write to log file: $($_.Exception.Message)"
	}
}


# UI Display Functions

<#
.SYNOPSIS
	Displays log file location if cartridges were dumped during this session
#>
function Show-LogFileLocation {
	if ($script:TIMESDUMPED -ge 1) {
		Write-Host "Log File: $script:LOG_FILE" -ForegroundColor Cyan
	}
}

<#
.SYNOPSIS
	Displays application header with ASCII art
#>
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
		" |__||_| \_||_____| |_| \_\___|\__|_|  \___/   |__||_| |_|\__\___|_|  |_|  \____|\___\___|",
		" ",
		"                                                      By: cosmickatamari | @cosmickatamari",
		"                                                       Last Updated: 11/11/2025 | ver. 10M",
		"------------------------------------------------------------------------------------------"
	)
	
	# Display ASCII art with gradient
	$gradientColors = @('Cyan', 'Cyan', 'DarkGreen', 'DarkGreen', 'DarkCyan', 'White', 'Yellow', 'Yellow', 'DarkGray')
	
	for ($i = 0; $i -lt $asciiLines.Count; $i++) {
		$color = $gradientColors[$i]
		Write-Host $asciiLines[$i] -ForegroundColor $color
	}
    
    Write-Host " "
	
	$Host.UI.RawUI.ForegroundColor = 'White'
}

<#
.SYNOPSIS
	Displays console selection menu
#>
function Select-Console {
	Write-Host "`n 1 - Nintendo Entertainment System" -ForegroundColor White
	Write-Host " 2 - Nintendo Famicom (Family Computer)" -ForegroundColor White
	Write-Host " 3 - Super Nintendo Entertainment System" -ForegroundColor White
	Write-Host " 4 - Nintendo 64" -ForegroundColor DarkGray
	Write-Host " 5 - Gameboy / Gameboy Advance" -ForegroundColor DarkGray
	Write-Host " 6 - Sega Genesis" -ForegroundColor DarkGray
	Write-Host " E - Exit" -ForegroundColor Yellow
	Write-Host
	
	while ($true) {
		$choice = Read-Host "Select A Console"
		
		# Check for exit command
		if ($choice -match '^[eE]$') {
            Write-Host " "
			Show-LogFileLocation
			Write-Host "Exiting INL Retro Interface. Goodbye!`n" -ForegroundColor DarkCyan
			exit 0
		}
		
		# Check for valid number
		$numChoice = 0
		if ([int]::TryParse($choice, [ref]$numChoice) -and $numChoice -ge 1 -and $numChoice -le 6) {
			return $script:consoleMap.($numChoice.ToString())
		}
		
		Write-Host "Please enter a number between 1-6, or 'E' to exit." -ForegroundColor Yellow
	}
}

<#
.SYNOPSIS
	Prompts user for cartridge name
#>
function Get-CartridgeName {
	param(
		[Parameter(Mandatory)]
		[string]$ConsoleName
	)
	
	while ($true) {
		$name = Read-Host "`nWhat's the name of your $ConsoleName game?"
		if ([string]::IsNullOrWhiteSpace($name)) { continue }
		return $name.Trim()
	}
}

<#
.SYNOPSIS
	Converts cartridge name to Windows-safe filename
#>
function ConvertTo-SafeFileName {
	param(
		[Parameter(Mandatory)]
		[string]$FileName
	)
	
	# Replace invalid characters with " - " for Windows compatibility
	# Characters: < > : " / \ |
	$safeName = $FileName -replace '[<>:"/\\|]', ' - '
	
	# Remove other invalid characters (strip out ? and *)
	$safeName = $safeName -replace '[?*]', ''
	
	# Trim any extra spaces that might have been created
	$safeName = $safeName -replace '\s+', ' ' -replace '^\s+|\s+$', ''
	
	return $safeName
}

<#
.SYNOPSIS
	Displays NES mapper selection menu
#>
function Select-Mapper {
	param(
		[Parameter(Mandatory)]
		[string]$CartridgeName
	)
	
	$baseurl = "https://nescartdb.com/search/basic?keywords="
	$endurl = "&kwtype=game"
	$encoded = [uri]::EscapeDataString($CartridgeName)
	$url = $baseurl + $encoded + $endurl

	# Open default browser and return focus to the script
	Open-UrlInDefaultBrowser-AndReturn -Url $url -DelayMs $script:BROWSER_NES_DELAY_MS

	Show-Header
	Write-Host "`nFor quicker access to important mapper information, the NES/Famicom database has opened to the search results from the game title.`n" -ForegroundColor Blue

	$columns = 5

	# Find the widest entry (number + name) so padding fits
	$maxLen = (0..($script:NESmapperMenu.Count - 1) | ForEach-Object {
		$num = ($_ + 1).ToString("00")
		(" {0}. {1}" -f $num, $script:NESmapperMenu[$_]).Length
	} | Measure-Object -Maximum).Maximum
	$colWidth = $maxLen + 4  # Add some extra spacing

	# Print mappers in table format
	for ($i = 0; $i -lt $script:NESmapperMenu.Count; $i++) {
		$num = ($i + 1).ToString("00")
		$text = " {0}. {1}" -f $num, $script:NESmapperMenu[$i]
		Write-Host ($text.PadRight($colWidth)) -NoNewline

		if ((($i + 1) % $columns) -eq 0) {
			Write-Host
		}
	}
	
	Write-Host "`nFor AxROM cartridges, select the BNROM mapper." -ForegroundColor Cyan
	Write-Host "For MHROM cartridges, select the GxROM mapper." -ForegroundColor Cyan
	Write-Host "For MMC6 cartridges, select the MMC3 mapper." -ForegroundColor Cyan
	
	while ($true) {
		$ans = Read-Int "`nMapper Number"
		if ($ans -ge 1 -and $ans -le $script:NESmapperMenu.Count) {
			return $script:NESmapperMenu[$ans - 1]
		}
		Write-Host ("Please choose between 1-{0}." -f $script:NESmapperMenu.Count) -ForegroundColor Yellow
	}
}


# SNES SRAM Detection Functions

<#
.SYNOPSIS
	Runs cartridge detection process and captures output
#>
function Invoke-CartridgeDetection {
	param(
		[Parameter(Mandatory)]
		[string]$TestExePath,
		
		[Parameter(Mandatory)]
		[string[]]$TestArgs
	)
	
	$headerOutput = ""
	$counter = 0
	$detectionStartTime = Get-Date
	$script:SessionStartTime = Get-Date  # Set session timer at start of detection
	
	# Start the process and read output line by line
	$process = Start-Process -FilePath $TestExePath -ArgumentList $TestArgs -NoNewWindow -PassThru -RedirectStandardOutput "temp_detection_output.txt" -RedirectStandardError "temp_detection_error.txt"
	
	# Show progress while running
	Write-Host "`n====[ Performing cartridge detection ]====" -ForegroundColor DarkCyan
	while (-not $process.HasExited) {
		$elapsed = (Get-Date) - $detectionStartTime
		$seconds = [math]::Floor($elapsed.TotalSeconds)
		if ($seconds -gt $counter) {
			$counter = $seconds
			Write-Host "`r====[ $seconds seconds ]====" -NoNewLine -ForegroundColor DarkCyan
		}
		Start-Sleep -Milliseconds $script:DETECTION_PROGRESS_INTERVAL_MS
	}
	
	# Wait for process to complete
	$process.WaitForExit()
	
	# Read the captured output
	if (Test-Path "temp_detection_output.txt") {
		$headerOutput = Get-Content "temp_detection_output.txt" -Raw
		Remove-Item "temp_detection_output.txt" -Force
	}
	if (Test-Path "temp_detection_error.txt") {
		$errorOutput = Get-Content "temp_detection_error.txt" -Raw
		$headerOutput += $errorOutput
		Remove-Item "temp_detection_error.txt" -Force
	}
	
	# Show completion (overwrites the timer line)
	$detectionElapsed = (Get-Date) - $detectionStartTime
	$detectionSeconds = [math]::Floor($detectionElapsed.TotalSeconds)
	$completionMsg = "====[ Detection completed in $detectionSeconds seconds, beginning cartridge processes. ]===="
	$paddedMsg = $completionMsg.PadRight($script:COMPLETION_MSG_PAD_LENGTH)
	Write-Host "`r$paddedMsg" -NoNewLine -ForegroundColor DarkCyan
	Write-Host ""
	Write-Host ""
	
	return $headerOutput
}

<#
.SYNOPSIS
	Detects SRAM size from header (Step 1)
#>
function Test-SRAMHeader {
	param(
		[Parameter(Mandatory)]
		[string]$HeaderOutput,
		
		[ref]$HasSRAM,
		
		[ref]$SramSizeKB,
		
		[ref]$DetectionMessages
	)
	
	$stepMsg = "Step 1: Checking header for SRAM Size"
	Write-Host $stepMsg -ForegroundColor Cyan
	$DetectionMessages.Value += $stepMsg
	
	$matched = $false
	
	# Check for SRAM Size in KB format
	if ($HeaderOutput -match "SRAM Size:\s*(\d+)K") {
		$size = [int]$matches[1]
		if ($size -gt 0) {
			$SramSizeKB.Value = $size
			$HasSRAM.Value = $true
			$foundMsg = "Found SRAM Size in header: $size KB."
			Write-Host $foundMsg -ForegroundColor Green
			$DetectionMessages.Value += $foundMsg
			$matched = $true
		}
	}
	# Check for SRAM Size in kilobits format
	elseif ($HeaderOutput -match "SRAM Size:\s*(\d+)\s*kilobits?") {
		$kb = [math]::Round([int]$matches[1] / 8)
		if ($kb -gt 0) {
			$SramSizeKB.Value = $kb
			$HasSRAM.Value = $true
			$foundMsg = "Found SRAM Size in header (kilobits): $kb KB."
			Write-Host $foundMsg -ForegroundColor Green
			$DetectionMessages.Value += $foundMsg
			$matched = $true
		}
	}
	
	if (-not $matched) {
		$noFoundMsg = "No SRAM Size found in header."
		Write-Host $noFoundMsg -ForegroundColor Yellow
		$DetectionMessages.Value += $noFoundMsg
	}
	
	Write-Host ""
	$DetectionMessages.Value += ""
	
	return $matched
}

<#
.SYNOPSIS
	Detects SRAM from runtime messages (Step 2)
#>
function Test-SRAMRuntime {
	param(
		[Parameter(Mandatory)]
		[string]$HeaderOutput,
		
		[ref]$HasSRAM,
		
		[ref]$SramSizeKB,
		
		[ref]$DetectionMessages,
		
		[bool]$SkipIfHeaderFound
	)
	
	$stepMsg = "Step 2: Checking for 'Save RAM Size'"
	Write-Host $stepMsg -ForegroundColor Cyan
	$DetectionMessages.Value += $stepMsg
	
	# Skip if header already found size
	if ($SkipIfHeaderFound) {
		$skipMsg = "SRAM size already found in header (Step 1), skipping runtime detection."
		Write-Host $skipMsg -ForegroundColor Green
		$DetectionMessages.Value += $skipMsg
		Write-Host ""
		$DetectionMessages.Value += ""
		return
	}
	
	# Only run checks if Step 1 didn't find the size
	if ($HeaderOutput -match "Save RAM Size.*?(\d+)\s*kilobytes?\s*detected") {
		$detectedSizeKB = [int]$matches[1]
		
		if ($detectedSizeKB -gt 0) {
			$foundMsg = "Found Save RAM Size: $detectedSizeKB KB."
			Write-Host $foundMsg -ForegroundColor Green
			$DetectionMessages.Value += $foundMsg
			$setMsg = "Detected size > 0, setting hasSRAM = true."
			Write-Host $setMsg -ForegroundColor Green
			$DetectionMessages.Value += $setMsg
			$HasSRAM.Value = $true
			$SramSizeKB.Value = $detectedSizeKB
		} else {
			$noRamMsg = "No Save RAM detected (size = 0 KB)."
			Write-Host $noRamMsg -ForegroundColor Yellow
			$DetectionMessages.Value += $noRamMsg
			$HasSRAM.Value = $false
			$SramSizeKB.Value = 0
		}
	} else {
		$noDetectMsg = "No 'Save RAM Size' detection found."
		Write-Host $noDetectMsg -ForegroundColor Yellow
		$DetectionMessages.Value += $noDetectMsg
	}
	
	Write-Host ""
	$DetectionMessages.Value += ""
}

<#
.SYNOPSIS
	Checks SRAM table size override
#>
function Test-SRAMTableSize {
	param(
		[Parameter(Mandatory)]
		[string]$HeaderOutput,
		
		[ref]$HasSRAM,
		
		[ref]$SramSizeKB,
		
		[ref]$DetectionMessages
	)
	
	# Check for the "Using SRAM table size" message which shows the final corrected size
	# This overrides header size, so always check it
	if ($HeaderOutput -match "Using SRAM table size: (\d+) KB") {
		$correctedSize = [int]$matches[1]
		if ($correctedSize -gt 0) {
			$HasSRAM.Value = $true
			$SramSizeKB.Value = $correctedSize
			$sramTableMsg = "SRAM table size detected: $correctedSize KB"
			Write-Host $sramTableMsg -ForegroundColor Green
			$DetectionMessages.Value += $sramTableMsg
		}
	}
}

<#
.SYNOPSIS
	Detects SRAM from hardware type (Step 3)
#>
function Test-SRAMHardwareType {
	param(
		[Parameter(Mandatory)]
		[string]$HeaderOutput,
		
		[ref]$HasSRAM,
		
		[ref]$SramSizeKB,
		
		[ref]$DetectionMessages
	)
	
	$stepMsg = "Step 3: Checking Hardware Type for Save RAM"
	Write-Host $stepMsg -ForegroundColor Cyan
	$DetectionMessages.Value += $stepMsg
	
	if ($HeaderOutput -match "Hardware Type:.*Save RAM") {
		$foundSaveRamMsg = "Found 'Save RAM' in Hardware Type."
		Write-Host $foundSaveRamMsg -ForegroundColor Green
		$DetectionMessages.Value += $foundSaveRamMsg
		
		# Set hasSRAM if not already set and size is 0
		if (-not $HasSRAM.Value -and $SramSizeKB.Value -eq 0) {
			# Check if this is a SuperFX game with Save RAM in hardware type
			if ($HeaderOutput -match "Hardware Type:.*SuperFX.*Save RAM") {
				$HasSRAM.Value = $true
				$SramSizeKB.Value = $script:SUPERFX_SRAM_SIZE_KB
				$superFxMsg = "SuperFX game with Save RAM detected - setting $($script:SUPERFX_SRAM_SIZE_KB)KB default."
				Write-Host $superFxMsg -ForegroundColor Green
				$DetectionMessages.Value += $superFxMsg
			} else {
				$HasSRAM.Value = $true
				$SramSizeKB.Value = $script:DEFAULT_SRAM_SIZE_KB
				$hwTypeMsg = "Hardware Type indicates Save RAM - setting hasSRAM = true, size will be auto-detected."
				Write-Host $hwTypeMsg -ForegroundColor Green
				$DetectionMessages.Value += $hwTypeMsg
			}
		} elseif ($HasSRAM.Value -and $SramSizeKB.Value -eq 0) {
			# SRAM was detected but size is still 0 - need to determine size
			if ($HeaderOutput -match "Hardware Type:.*SuperFX.*Save RAM") {
				$SramSizeKB.Value = $script:SUPERFX_SRAM_SIZE_KB
				$superFxMsg = "SuperFX game with Save RAM detected - setting $($script:SUPERFX_SRAM_SIZE_KB)KB size."
				Write-Host $superFxMsg -ForegroundColor Green
				$DetectionMessages.Value += $superFxMsg
			} else {
				$SramSizeKB.Value = $script:DEFAULT_SRAM_SIZE_KB
				$hwTypeMsg = "Hardware Type indicates Save RAM - setting $($script:DEFAULT_SRAM_SIZE_KB)KB default."
				Write-Host $hwTypeMsg -ForegroundColor Green
				$DetectionMessages.Value += $hwTypeMsg
			}
		}
		# If we already have hasSRAM and size, silently confirm (no redundant output)
	} else {
		# Only report absence if we don't have SRAM confirmed yet
		if (-not ($HasSRAM.Value -and $SramSizeKB.Value -gt 0)) {
			$noSaveRamMsg = "No 'Save RAM' found in Hardware Type."
			Write-Host $noSaveRamMsg -ForegroundColor Yellow
			$DetectionMessages.Value += $noSaveRamMsg
		}
	}
	
	$DetectionMessages.Value += ""
}

<#
.SYNOPSIS
	Detects SuperFX SRAM from expansion RAM field (Step 4)
#>
function Test-SuperFXExpansionRAM {
	param(
		[Parameter(Mandatory)]
		[string]$HeaderOutput,
		
		[ref]$HasSRAM,
		
		[ref]$SramSizeKB,
		
		[ref]$DetectionMessages
	)
	
	# Check for Super FX games with SRAM size in Expansion RAM Size field
	# According to Super Nintendo documentation: Super FX games store SRAM size in Expansion RAM Size field
	# Only check if we haven't found SRAM yet
	if ($HeaderOutput -match "Hardware Type:.*SuperFX.*Save RAM" -and $HeaderOutput -match "SRAM Size:\s*None") {
		$stepMsg = "Step 4: Checking for SuperFX + Save RAM + SRAM Size None"
		Write-Host $stepMsg -ForegroundColor Cyan
		$DetectionMessages.Value += $stepMsg
		
		$foundSuperFxMsg = "Found SuperFX with Save RAM and SRAM Size None."
		Write-Host $foundSuperFxMsg -ForegroundColor Green
		$DetectionMessages.Value += $foundSuperFxMsg
		
		$checkExpMsg = "Super FX game detected with Save RAM - checking Expansion RAM Size field."
		Write-Host $checkExpMsg -ForegroundColor Cyan
		$DetectionMessages.Value += $checkExpMsg
		
		if ($HeaderOutput -match "Expansion RAM Size:\s*(\d+)\s*kilobits") {
			$expRamKBits = [int]$matches[1]
			$foundExpMsg = "Found Expansion RAM: ${expRamKBits} kilobits."
			Write-Host $foundExpMsg -ForegroundColor Cyan
			$DetectionMessages.Value += $foundExpMsg
			
			# Convert kilobits to KB
			$expRamKB = [math]::Round($expRamKBits / 8)
			$convertMsg = "Converted: ${expRamKBits} kilobits = $expRamKB KB."
			Write-Host $convertMsg -ForegroundColor Cyan
			$DetectionMessages.Value += $convertMsg
			
			# For Super FX games, this expansion RAM size IS the SRAM size
			$HasSRAM.Value = $true
			$superFxDetectedMsg = "Super FX SRAM detected via Expansion RAM field: ${expRamKBits} kilobits = ${expRamKB}KB."
			Write-Host $superFxDetectedMsg -ForegroundColor Green
			$DetectionMessages.Value += $superFxDetectedMsg
			
			$SramSizeKB.Value = $expRamKB
		}
	} else {
		# Only report failure if we don't have SRAM confirmed yet
		if (-not ($HasSRAM.Value -and $SramSizeKB.Value -gt 0)) {
			$noSuperFxMsg = "Conditions not met for SuperFX detection."
			Write-Host $noSuperFxMsg -ForegroundColor Yellow
			$DetectionMessages.Value += $noSuperFxMsg
		}
	}
	
	Write-Host ""
	$DetectionMessages.Value += ""
}

<#
.SYNOPSIS
	Performs complete SRAM detection for SNES cartridges
#>
function Invoke-SNESSRAMDetection {
	param(
		[Parameter(Mandatory)]
		[string]$HeaderOutput
	)
	
	$hasSRAM = $false
	$sramSizeKB = 0
	$detectionMessages = @()
	
	try {
		# Step 1: Check header for SRAM Size
		$headerFound = Test-SRAMHeader -HeaderOutput $HeaderOutput -HasSRAM ([ref]$hasSRAM) -SramSizeKB ([ref]$sramSizeKB) -DetectionMessages ([ref]$detectionMessages)
		
		# Step 2: Check for runtime detection messages (only if Step 1 didn't find header size)
		Test-SRAMRuntime -HeaderOutput $HeaderOutput -HasSRAM ([ref]$hasSRAM) -SramSizeKB ([ref]$sramSizeKB) -DetectionMessages ([ref]$detectionMessages) -SkipIfHeaderFound $headerFound
		
		# Check SRAM table size override (always check - overrides header size)
		Test-SRAMTableSize -HeaderOutput $HeaderOutput -HasSRAM ([ref]$hasSRAM) -SramSizeKB ([ref]$sramSizeKB) -DetectionMessages ([ref]$detectionMessages)
		
		# Step 3: Check Hardware Type for "Save RAM" indication
		Test-SRAMHardwareType -HeaderOutput $HeaderOutput -HasSRAM ([ref]$hasSRAM) -SramSizeKB ([ref]$sramSizeKB) -DetectionMessages ([ref]$detectionMessages)
		
		# Step 4: Check for Super FX games with SRAM size in Expansion RAM Size field
		Test-SuperFXExpansionRAM -HeaderOutput $HeaderOutput -HasSRAM ([ref]$hasSRAM) -SramSizeKB ([ref]$sramSizeKB) -DetectionMessages ([ref]$detectionMessages)
		
		# Ensure hasSRAM is false if size is 0
		if (-not ($hasSRAM -and $sramSizeKB -gt 0)) {
			$hasSRAM = $false
		}
	} catch {
		Write-Warning "Could not detect SRAM configuration, assuming no SRAM exists."
		$hasSRAM = $false
		$sramSizeKB = 0
	}
	
	return @{
		HasSRAM = $hasSRAM
		SramSizeKB = $sramSizeKB
		DetectionMessages = $detectionMessages
	}
}


# Core Dumping Functions

<#
.SYNOPSIS
	Handles NES/Famicom cartridge dumping workflow
#>
function Invoke-NESBasedCartridgeDump {
	param(
		[Parameter(Mandatory)]
		[string]$ConsoleFolderName,
		
		[Parameter(Mandatory)]
		[string]$CartridgeName
	)
	
	$nesmap = Select-Mapper -CartridgeName $CartridgeName
	$prg = Read-KB-MultipleOf4 "`nWhat is the size (in KB) of the Program (PRG) ROM? (typically PRG0)"
	$hasChr = Read-YesNo "`nDoes the cartridge have a Character (CHR) ROM? (typically CHR0)"
	
	if ($hasChr) { 
		$chr = Read-KB-MultipleOf4 "What is the size (in KB) of the Character ROM?" 
	}

	$hasSRAM = Read-YesNo "`nDoes the cartridge contain a battery save (Working RAM)?"

	# Paths for storing files
	$gamesRoot = Join-Path $PSScriptRoot "games\$ConsoleFolderName"
	$sramRoot = Join-Path $gamesRoot 'sram'
	$cartDest = Join-Path $gamesRoot "$CartridgeName.nes"
	$sramDest = Join-Path $sramRoot "$CartridgeName.sav"
	
	# Create directories on-demand
	[void](New-Item -ItemType Directory -Path $gamesRoot -Force)
	[void](New-Item -ItemType Directory -Path $sramRoot -Force)
	[void](New-Item -ItemType Directory -Path $script:LOG_DIR -Force)

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

<#
.SYNOPSIS
	Executes inlretro.exe with provided arguments and handles output
#>
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

	# Format command string for display
	$pretty = (
		$ArgsArray | ForEach-Object {
			if ($_ -match '[\s"]') { '"' + ($_ -replace '"','`"') + '"' } else { $_ }
		}
	) -join ' '

	# Only show command if not a redump
	if (-not $IsRedump) {
		Write-Host ".\inlretro.exe $pretty" -ForegroundColor DarkCyan
		Write-Host ""
	}

	# Execute with direct call operator to ensure real-time output display
	$exitCode = 0
	
	try {
		& $exePath @ArgsArray 2>&1 | ForEach-Object {
			$_ | Write-Host
		}
		$exitCode = $LASTEXITCODE
	} catch {
		Write-Error "Failed to execute inlretro.exe: $($_.Exception.Message)"
		$exitCode = -1
	}
	
	Write-Host

	if ($exitCode -ne 0) {
		Write-Host "inlretro.exe exited with code $exitCode." -ForegroundColor Red
		Write-Host "The cartridge could not be dumped." -ForegroundColor Red
		
		# Log failed attempt
		if ($IsRedump) {
			$redumpMessage = "Re-running previous cartridge dump command. Subsequent dump attempts are saved with incrementing identifiers appended to the output file name."
			Write-DumpLog -CommandString $redumpMessage -CartridgeFile $CartDest -SramFile $SramDest -Success $false -DetectionInfo $DetectionInfo -CartridgeTitle $CartridgeTitle
		} else {
			Write-DumpLog -CommandString $pretty -CartridgeFile $CartDest -SramFile $SramDest -Success $false -DetectionInfo $DetectionInfo -CartridgeTitle $CartridgeTitle
		}
		
		return $false
	}
	
	if ($exitCode -eq 0) {
		$script:TIMESDUMPED++
		
		# Build process summary for logging (file analysis details with locations)
		$processSummary = @()
		
		# Get ROM file analysis
		if (Test-Path $CartDest) {
			$processSummary += "Cartridge game ROM location: $CartDest"
			$romAnalysis = @(Get-FileAnalysisText -FilePath $CartDest -FileType "ROM")
			if ($romAnalysis.Count -gt 0) {
				$processSummary += $romAnalysis
			}
		}
		
		# Get SRAM file analysis if SRAM was created
		if ($HasSRAM -and (Test-Path $SramDest)) {
			if ($processSummary.Count -gt 0) {
				$processSummary += ""  # Add blank line between ROM and SRAM analysis
			}
			$processSummary += "Cartridge save data location: $SramDest"
			$sramAnalysis = @(Get-FileAnalysisText -FilePath $SramDest -FileType "SRAM")
			if ($sramAnalysis.Count -gt 0) {
				$processSummary += $sramAnalysis
			}
		}
		
		# Log successful dump
		if ($IsRedump) {
			$redumpMessage = "Re-running previous cartridge dump command. Subsequent dump attempts are saved with incrementing identifiers appended to the output file name."
			Write-DumpLog -CommandString $redumpMessage -CartridgeFile $CartDest -SramFile $SramDest -Success $true -DetectionInfo $DetectionInfo -IsRedump $true -CartridgeTitle $CartridgeTitle -ProcessSummary ($processSummary -join "`n")
		} else {
			Write-DumpLog -CommandString $pretty -CartridgeFile $CartDest -SramFile $SramDest -Success $true -DetectionInfo $DetectionInfo -IsRedump $false -CartridgeTitle $CartridgeTitle -ProcessSummary ($processSummary -join "`n")
		}
		
		# Display console output for ROM/SRAM information
		Write-Host "====[ Process Summary ]====" -ForegroundColor Cyan
		Write-Host ""
		Write-Host "Cartridge game ROM location: " -NoNewline -ForegroundColor Cyan
		Write-Host "$CartDest" -ForegroundColor Magenta
		
		# Display cartridge ROM file analysis
		Show-FileAnalysis -FilePath $CartDest -FileType "ROM"
		
		# Check if SRAM file was actually created
		if ($HasSRAM -and (Test-Path $SramDest)) {
			Write-Host ""
			Write-Host "Cartridge save data location: " -NoNewline -ForegroundColor Cyan
			Write-Host "$SramDest" -ForegroundColor Magenta
			
			Show-FileAnalysis -FilePath $SramDest -FileType "SRAM"
			
		} elseif ($HasSRAM -and -not (Test-Path $SramDest)) {
			# PowerShell detected SRAM but Lua script determined no SRAM file should be created
			Write-Host "No save data found, the cartridge does not have SRAM or the battery is dead." -ForegroundColor Yellow
			Write-Host "The LUA script correctly determined this cartridge has no usable save RAM." -ForegroundColor Cyan
			Write-Host ""
		}
		
		return $true
	}
}

<#
.SYNOPSIS
	Handles redump functionality - allows multiple dump attempts
#>
function ReDump {
	# Check if parameters from a previous dump exist
	if ($null -eq $script:LastArgsArray) {
		return  # No previous dump to redo
	}

	# Redumping will continue until the choice is 'n'
	while ($true) {
		Write-Host ""
		Write-Host "If the ROM is not working as expected, reseat or clean cartridge contacts before reattempting."
		Write-Host "WHEN CLEANING: NEVER USE BRASSO!" -ForegroundColor Red
		Write-Host ""
		
		# Display cleaning instructions with option to open URL (only first time)
		if (-not $script:BrowserPromptShown) {
			$openLink = Read-YesNo "Would you like to access the RetroRGB.com article on cleaning best practices?"
			if ($openLink) {
				Open-UrlInDefaultBrowser-AndReturn -Url "https://www.retrorgb.com/cleangames.html"
			}
		
			$script:BrowserPromptShown = $true
		}
		
		$rerun = Read-YesNo "Proceed with another attempt? (An incremental version will be made.)"
		
		if ($rerun) {
			Write-Host ""
			Write-Host "====[ Performing cartridge redump ]====" -ForegroundColor DarkCyan
			
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
			
			$redumpSuccess = Invoke-INLRetro -ArgsArray $newArgsArray -CartDest $newCartDest -SramDest $newSramDest -HasSRAM $script:LastHasSRAM -IsRedump $true -CartridgeTitle ""
			
			if (-not $redumpSuccess) {
				Write-Host ""
				Write-Host "Redump attempt failed. Exiting application." -ForegroundColor Red
				Show-LogFileLocation
				exit 1
			}
		
		} else {
			# Prompt with default 'y' (different from Read-YesNo which defaults to 'n')
			while ($true) {
				$v = (Read-Host "Would you like to dump another game cartridge? (y/n, default: y)").Trim().ToLower()
				if ($v -eq '') { $dumpAnother = $true; break }  # Default to 'y' (true)
				if ($v -eq 'y') { $dumpAnother = $true; break }
				if ($v -eq 'n') { $dumpAnother = $false; break }
				Write-Host "Please enter Y or N (or press [ENTER] for default: Y)." -ForegroundColor Yellow
			}
			
			if ($dumpAnother) {
				# User wants to dump another - break out of redump loop to start new dump
				break
			} else {
				# User doesn't want to dump another - exit
				Write-Host " "
                Show-LogFileLocation
                Write-Host "Exiting INL Retro Dumper Interface. Goodbye!" -ForegroundColor DarkCyan
				exit 0
			}
		}
	}
}


# Main Execution

# Main Dumping Execution
while ($true) {
	try {
		Show-Header
		$sys = Select-Console
		$cartridge = Get-CartridgeName -ConsoleName $sys
		
		# Convert cartridge name to safe filename
		$safeCartridgeName = ConvertTo-SafeFileName -FileName $cartridge
		
		# Reset browser prompt flag for new cartridge
		$script:BrowserPromptShown = $false
		
		switch ($sys) {
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
				[void](New-Item -ItemType Directory -Path $script:LOG_DIR -Force)

				# Run cartridge detection
				$testArgs = @('-s', $luaScript, '-c', 'SNES', '-d', 'NUL', '-a', 'NUL')
				$testExePath = Join-Path $PSScriptRoot 'inlretro.exe'
				
				Write-Host ""
				
				try {
					$headerOutput = Invoke-CartridgeDetection -TestExePath $testExePath -TestArgs $testArgs
					
					# Perform SRAM detection
					$detectionResult = Invoke-SNESSRAMDetection -HeaderOutput $headerOutput
					$hasSRAM = $detectionResult.HasSRAM
					$sramSizeKB = $detectionResult.SramSizeKB
					$detectionMessages = $detectionResult.DetectionMessages
					
				} catch {
					Write-Warning "Could not detect SRAM configuration, assuming no SRAM exists."
					$hasSRAM = $false
					$sramSizeKB = 0
					$detectionMessages = @()
				}

				# The Legend of Zelda: A Link to the Past stores a 32KB save file but
				# frequently reports no SRAM in the header. Force a full 32KB dump so
				# the save data at $7E:F000-$7E:F4FE (mirrored from SRAM) is captured.
				if ($headerOutput -match "Rom Title:\s*(.+?)(?:\r?\n|$)") {
					$cartTitle = $matches[1].Trim()
				} else {
					$cartTitle = ""
				}

				if ((($cartTitle -match 'LINK' -and $cartTitle -match 'PAST') -or ($cartTitle -match 'LEGEND\s+OF\s+ZELDA')) -and ($sramSizeKB -lt 32)) {
					$hasSRAM = $true
					$sramSizeKB = 32
					$detectionMessages += "Link to the Past detected - overriding SRAM dump size to 32KB based on annotated save documentation."
				}
				
				# Extract cartridge title from header output
				if (-not $cartTitle) {
					if ($headerOutput -match "Rom Title:\s*(.+?)(?:\r?\n|$)") {
						$cartTitle = $matches[1].Trim()
					}
				}
				
				# Prepare detection information for logging
				$detectionInfo = "`n" + ($detectionMessages -join "`n")
				
				# Add cartridge information to the log
				$cartridgeInfo = @(Get-CartridgeInfo -HeaderOutput $headerOutput)
				
				# Add SRAM size from detection if header parsing failed
				if ($cartridgeInfo.Count -eq 0 -and $headerOutput -match "Could not parse internal ROM header") {
					if ($hasSRAM -and $sramSizeKB -gt 0) {
						# Convert KB to kilobits for display
						$sramKbits = $sramSizeKB * 8
						$cartridgeInfo += "SRAM Size:              $sramKbits kilobits"
					}
				}
				
				# Add cartridge info to detection info for logging
				if ($cartridgeInfo.Count -gt 0) {
					$detectionInfo += "`nCartridge Info:"
					$detectionInfo += "`n" + ($cartridgeInfo -join "`n")
					$detectionInfo += "`n"
				}

				$headerDetected = ($headerOutput -match "Rom Title:") -or ($headerOutput -match "Valid header found")
				if (-not $headerDetected) {
					Open-UrlInDefaultBrowser-AndReturn -Url "https://www.retrorgb.com/cleangames.html"
					Write-Host ""
					Write-Host "The cartridge's Mask ROM can not be detected." -ForegroundColor Yellow
					Write-Host "Please ensure that the cartridge is clean and functional on gaming hardware." -ForegroundColor Yellow
					Show-LogFileLocation
					exit 1
				}
				
				# Build complete arguments for both ROM and SRAM in single process
				$argsArray = @('-s', $luaScript, '-c', 'SNES', '-d', $cartDest)
				
				if ($hasSRAM -and $sramSizeKB -gt 0) {
					$argsArray += @('-a', $sramDest, '-w', "$sramSizeKB")
					Write-Host "Program parameters used (game ROM and save data):" -ForegroundColor Cyan
				} else {
					Write-Host "Program parameters used (only game ROM, no save data detected):" -ForegroundColor Cyan
				}

				$dumpSuccess = Invoke-INLRetro -ArgsArray $argsArray -CartDest $cartDest -SramDest $sramDest -HasSRAM $hasSRAM -CartridgeTitle $cartTitle -DetectionInfo $detectionInfo

				if ($dumpSuccess) {
					# Display session timing message after successful dump
					Write-Host ""
					$sessionTimeFormatted = Format-SessionTime -StartTime $script:SessionStartTime
					if ($sessionTimeFormatted -ne "") {
						Write-Host "====[ During this session, you have created $script:TIMESDUMPED cartridge dump(s) in $sessionTimeFormatted. ]====" -ForegroundColor DarkCyan
					}
					ReDump
				} else {
					Write-Host "The dump failed. Please check the error messages above." -ForegroundColor Red
					Write-Host "Exiting due to failure." -ForegroundColor Red
					Show-LogFileLocation
					exit 1
				}
			}
			
			'Nintendo 64' {
				# N64 (placeholder)
				Write-Host "Add args as needed." -ForegroundColor Yellow
				Read-Host
			}
			
			'Gameboy / Gameboy Advance' {
				# Gameboy / GBA (placeholder)
				Write-Host "Add args as needed." -ForegroundColor Yellow
				Read-Host
			}
			
			'Sega Genesis' {
				# Sega Genesis (placeholder)
				Write-Host "Add args as needed." -ForegroundColor Yellow
				Read-Host
			}
		}
		
	} catch {
		Write-Host "`n`nWARNING: A fatal error occurred during operation:" -ForegroundColor Red
		Write-Host $_.Exception.Message -ForegroundColor Red
		Write-Host "`nStack Trace:" -ForegroundColor Yellow
		Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
		Write-Host "`nExiting application..." -ForegroundColor Cyan
		Show-LogFileLocation
		exit 1
	}
}

