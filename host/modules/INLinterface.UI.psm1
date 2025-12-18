# INLinterface.UI.psm1
# Functions for displaying menus, headers, and user interface elements.
# This module handles all user interface operations including menus, headers, and user prompts.

<#
	Displays log file location if cartridges were dumped during this session.
	Shows the path to the current session's log file only if at least one cartridge has been dumped.
	Used at script exit to inform the user where they can find the operation log.
#>
function Show-LogFileLocation {
	param(
		[int]$TimesDumped,
		[string]$LogFile
	)
	
	if ($TimesDumped -ge 1) {
		Write-Host "Log File: $LogFile" -ForegroundColor Cyan
	}
}

<#
	Displays application header with ASCII art.
	Clears the screen, positions the window optimally, and displays a formatted ASCII art header
	with gradient colors. Includes author information, last updated date, and version number.
	Resets the console foreground color to white after display.
#>
function Show-Header {
	Clear-Host
	
	$asciiLines = @(
		"  __  _   _  _       ____      _                __        _             __                ",
		" |__|| \ | || |     |  _ \ ___| |_ ____ ___    |__| ____ | |_ ___ ____ / _| ____  ___ ___ ",
		"  || |  \| || |     | |_) / _ \ __|  __/ _ \    || |  _ \| __/ _ \  __| |_ / _  |/ __/ _ \",
		"  || | |\  || |___  |  _ <  __/ |_| | | (_) |   || | | | | |_| __/ |  |  _| (_| | (_|  __/",
		" |__||_| \_||_____| |_| \_\___|\__|_|  \___/   |__||_| |_|\__\___|_|  |_|  \____|\___\___|",
		" ",
		"                                                      By: cosmickatamari | @cosmickatamari",
		"                                                       Last Updated: 12/17/2025 | ver. 10p",
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
	Displays console selection menu.
	Shows a numbered list of supported consoles (NES, Famicom, SNES, N64, Gameboy/GBA, Sega Genesis)
	with an option to exit. Validates user input and returns the selected console name.
	Continues prompting until a valid selection is made or the user chooses to exit.
#>
function Select-Console {
	param(
		[string]$LogFile,
		[int]$TimesDumped,
		[string]$IgnoreDir
	)
	
	# Console name mapping (hardcoded to match menu display)
	$consoleMap = @{
		'1' = 'Nintendo Entertainment System'
		'2' = 'Nintendo Famicom (Family Computer)'
		'3' = 'Super Nintendo Entertainment System'
		'4' = 'Nintendo 64'
		'5' = 'Gameboy / Gameboy Advance'
		'6' = 'Sega Genesis'
	}
	
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
			Show-LogFileLocation -TimesDumped $TimesDumped -LogFile $LogFile
			Write-Host "Exiting INL Retro Interface. Goodbye!`n" -ForegroundColor DarkCyan
			Remove-IgnoreFolder -IgnoreDir $IgnoreDir
			exit 0
		}
		
		# Check for valid number
		$numChoice = 0
		if ([int]::TryParse($choice, [ref]$numChoice) -and $numChoice -ge 1 -and $numChoice -le 6) {
			return $consoleMap[$choice]
		}
		
		Write-Host "Please enter a number between 1-6, or 'E' to exit." -ForegroundColor Yellow
	}
}

<#
	Prompts user for cartridge name.
	Asks the user to enter the name of their game cartridge for the specified console.
	Validates that the input is not empty or whitespace and returns the trimmed cartridge name.
	Continues prompting until a valid name is entered.
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
	Displays NES mapper selection menu.
	Opens the NES Cart Database in the default browser with search results for the cartridge name,
	then displays a formatted table of available NES mappers. Shows helpful notes about mapper
	equivalencies (AxROM->BNROM, MHROM->GxROM, MMC6->MMC3). Validates user input and returns
	the selected mapper name. Continues prompting until a valid mapper number is selected.
#>
function Select-Mapper {
	param(
		[Parameter(Mandatory)]
		[string]$CartridgeName,
		
		[array]$NESmapperMenu,
		
		[int]$BrowserNesDelayMs
	)
	
	$baseurl = "https://nescartdb.com/search/basic?keywords="
	$endurl = "&kwtype=game"
	$encoded = [uri]::EscapeDataString($CartridgeName)
	$url = $baseurl + $encoded + $endurl

	# Open default browser and return focus to the script
	Open-UrlInDefaultBrowser-AndReturn -Url $url -DelayMs 750

	Show-Header
	Write-Host "`nFor quicker access to important mapper information, the NES/Famicom database has opened to the search results from the game title.`n" -ForegroundColor Blue

	$columns = 5

	# Find the widest entry (number + name) so padding fits
	$maxLen = (0..($NESmapperMenu.Count - 1) | ForEach-Object {
		$num = ($_ + 1).ToString("00")
		(" {0}. {1}" -f $num, $NESmapperMenu[$_]).Length
	} | Measure-Object -Maximum).Maximum
	$colWidth = $maxLen + 4  # Add some extra spacing

	# Print mappers in table format
	for ($i = 0; $i -lt $NESmapperMenu.Count; $i++) {
		$num = ($i + 1).ToString("00")
		$text = " {0}. {1}" -f $num, $NESmapperMenu[$i]
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
		if ($ans -ge 1 -and $ans -le $NESmapperMenu.Count) {
			return $NESmapperMenu[$ans - 1]
		}
		Write-Host ("Please choose between 1-{0}." -f $NESmapperMenu.Count) -ForegroundColor Yellow
	}
}

Export-ModuleMember -Function Show-LogFileLocation, Show-Header, Select-Console, Get-CartridgeName, Select-Mapper

