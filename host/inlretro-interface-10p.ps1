<#
	INL Retro Dumper Interface - An interactive cartridge dumping tool.

	Interactive PowerShell interface for dumping retro game cartridges using the INL Retro Dumper hardware.
	Supports multiple cartridge based systems from the 8 and 16 bit era.

	Author: Cosmic Katamari (@cosmickatamari)
	Twitter/X: @cosmickatamari
	Last Updated: 12/17/2025
	Requires: PowerShell 7.x or higher

	GitHub Project: https://github.com/cosmickatamari/INL-retro-progdump
	Original Author's Project: https://gitlab.com/InfiniteNesLives/INL-retro-progdump
	Cart dumper purchase link: https://www.infiniteneslives.com/inlretro.php
	3D printed case purchase link: (need to upload)
	3D printed case can self-printed link: https://www.printables.com/model/2808-inlretro-dumper-programmer-case-v2

	This script acts as the interactive front-end for INL's retro dumper hardware.
	It performs host validation, loads console metadata, guides the user through
	cartridge-specific prompts, runs the dumping executable, and writes detailed logs.
	High-level flow:
		1) Validate PowerShell version and console window size.
		2) Load mapper/console metadata plus ensure temp/log folders exist.
		3) Guide the user through console + cartridge specific prompts.
		4) Run cartridge detection/dumping, summarize results, and enable redumps.
#>

#Requires -Version 7.0

[CmdletBinding()]
param()

# Enable strict mode for better error detection
Set-StrictMode -Version Latest

# Import modules in dependency order
# Using -DisableNameChecking to suppress warnings about function names with multiple hyphens
Import-Module "$PSScriptRoot\modules\INLinterface.Utility.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\modules\INLinterface.Window.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\modules\INLinterface.Browser.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\modules\INLinterface.FileAnalysis.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\modules\INLinterface.Logging.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\modules\INLinterface.UI.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\modules\INLinterface.Dumping.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\modules\INLinterface.Consoles.psm1" -Force -DisableNameChecking
# Note: Console-specific modules (NES, SNES, etc.) and SNESDetection are loaded dynamically when needed

# Global Configuration & State
# This section contains all global constants, variables, and configuration settings used throughout the script.

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

# Ignore folder for temporary detection files
$script:IGNORE_DIR = Join-Path $PSScriptRoot "ignore"

# Environment Validation
# Validates that the PowerShell environment meets the script's requirements (currently 7.x)

if ($PSVersionTable.PSVersion.Major -lt 7) {
	Clear-Host
	
	Write-Host "--- WARNING ---" -ForegroundColor Red
	Write-Host "`nThis script requires " -NoNewline -ForegroundColor Yellow
	Write-Host "PowerShell 7" -NoNewline -ForegroundColor Magenta
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
	Remove-IgnoreFolder -IgnoreDir $script:IGNORE_DIR
	exit 1
}

# Data & Configuration Files
# Loading and validation of external JSON configuration files containing console and mapper data.
# Initialize data directory
$dataDir = Join-Path $PSScriptRoot "data"
[void](New-Item -ItemType Directory -Path $dataDir -Force)

# Load external data files
try {
	$script:NESmapperMenu = Get-Content (Join-Path $dataDir "nes-mappers.json") -ErrorAction Stop | ConvertFrom-Json
	Write-Host "Configuration and data files loaded successfully." -ForegroundColor Green
} catch {
	Write-Error "Failed to load required data files from $dataDir"
	Write-Error "Please ensure the following files exist:"
	Write-Error "  - nes-mappers.json"
	Write-Error "`n The latest release can be downloaded at: https://github.com/cosmickatamari/inlretro-interface"
	Start-Process "https://github.com/cosmickatamari/inlretro-interface"
	Write-Error "`nError details: $($_.Exception.Message)"
	
	Remove-IgnoreFolder -IgnoreDir $script:IGNORE_DIR
	exit 1
}

# Main Execution Loop
# The primary execution loop that drives the entire application workflow.
while ($true) {
	# Each iteration walks the user through selecting a console, dumping a single cartridge, and optionally performing redumps before returning to the menu.
	try {
		Show-Header
		Set-WindowPosition
		$sys = Select-Console -LogFile $script:LOG_FILE -TimesDumped $script:TIMESDUMPED -IgnoreDir $script:IGNORE_DIR
		$cartridge = Get-CartridgeName -ConsoleName $sys
		
		# Convert cartridge name to safe filename
		$safeCartridgeName = ConvertTo-SafeFileName -FileName $cartridge
		
		# Reset browser prompt flag for new cartridge
		$script:BrowserPromptShown = $false
		
		# Route to console-specific dumping workflow
		Invoke-ConsoleDump -ConsoleName $sys -CartridgeName $safeCartridgeName -PSScriptRoot $PSScriptRoot -LogDir $script:LOG_DIR -IgnoreDir $script:IGNORE_DIR -LogFile $script:LOG_FILE -NESmapperMenu $script:NESmapperMenu -TimesDumped ([ref]$script:TIMESDUMPED) -LastArgsArray ([ref]$script:LastArgsArray) -LastCartDest ([ref]$script:LastCartDest) -LastSramDest ([ref]$script:LastSramDest) -LastHasSRAM ([ref]$script:LastHasSRAM) -BaseCartDest ([ref]$script:BaseCartDest) -BaseSramDest ([ref]$script:BaseSramDest) -BrowserPromptShown ([ref]$script:BrowserPromptShown) -SessionStartTime ([ref]$script:SessionStartTime)
		
	} catch {
		Write-Host "`n`nWARNING: A fatal error occurred during operation:" -ForegroundColor Red
		Write-Host $_.Exception.Message -ForegroundColor Red
		Write-Host "`nStack Trace:" -ForegroundColor Yellow
		Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
		Write-Host "`nExiting application..." -ForegroundColor Cyan
		Show-LogFileLocation -TimesDumped $script:TIMESDUMPED -LogFile $script:LOG_FILE
		Remove-IgnoreFolder -IgnoreDir $script:IGNORE_DIR
		exit 1
	}
}

