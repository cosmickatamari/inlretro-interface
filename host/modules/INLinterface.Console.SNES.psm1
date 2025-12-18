# INLinterface.Console.SNES.psm1
# Super Nintendo Entertainment System console-specific dumping workflow.
# This module handles the complete SNES cartridge dumping process including SRAM detection.

<#
	Handles Super Nintendo Entertainment System cartridge dumping workflow.
	Performs cartridge detection, SRAM detection, executes the dump, and handles post-dump operations.
	Returns true on success, false on failure, or exits the application on critical errors.
#>
function Invoke-SNESDump {
	param(
		[Parameter(Mandatory)]
		[string]$CartridgeName,
		
		[string]$PSScriptRoot,
		
		[string]$LogDir,
		
		[string]$IgnoreDir,
		
		[string]$LogFile,
		
		[ref]$TimesDumped,
		
		[ref]$LastArgsArray,
		
		[ref]$LastCartDest,
		
		[ref]$LastSramDest,
		
		[ref]$LastHasSRAM,
		
		[ref]$BaseCartDest,
		
		[ref]$BaseSramDest,
		
		[ref]$BrowserPromptShown,
		
		[ref]$SessionStartTime
	)
	
	# Dynamically import SNESDetection module when SNES dumping is needed
	$snesDetectionModule = Join-Path $PSScriptRoot "modules\INLinterface.SNESDetection.psm1"
	if (-not (Get-Module -Name "INLinterface.SNESDetection")) {
		Import-Module $snesDetectionModule -Force -DisableNameChecking -ErrorAction Stop
	}
	
	$gamesRoot = Join-Path $PSScriptRoot 'games\snes'
	$sramRoot = Join-Path $gamesRoot 'sram'
	$cartDest = Join-Path $gamesRoot "$CartridgeName.smc"
	$sramDest = Join-Path $sramRoot "$CartridgeName.srm"
	$luaScript = Join-Path $PSScriptRoot 'scripts\inlretro2.lua'
	
	[void](New-Item -ItemType Directory -Path $gamesRoot -Force)
	[void](New-Item -ItemType Directory -Path $sramRoot -Force)
	[void](New-Item -ItemType Directory -Path $LogDir -Force)

	# Run cartridge detection
	$testArgs = @('-s', $luaScript, '-c', 'SNES', '-d', 'NUL', '-a', 'NUL')
	$testExePath = Join-Path $PSScriptRoot 'inlretro.exe'
	
	Write-Host ""
	
	try {
		$headerOutput = Invoke-CartridgeDetection -TestExePath $testExePath -TestArgs $testArgs -IgnoreDir $IgnoreDir -SessionStartTime $SessionStartTime
		
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

	# Extract cartridge title from header output
	if ($headerOutput -match "Rom Title:\s*(.+?)(?:\r?\n|$)") {
		$cartTitle = $matches[1].Trim()
	} else {
		$cartTitle = ""
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
	
	# Extract correct version from parsed cartridge info for filtering dump output
	$correctVersion = $null
	foreach ($infoLine in $cartridgeInfo) {
		if ($infoLine -match "^Version\s+(\S+)") {
			$correctVersion = $matches[1].Trim()
			break
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
		Show-LogFileLocation -TimesDumped $TimesDumped.Value -LogFile $LogFile
		Remove-IgnoreFolder -IgnoreDir $IgnoreDir
		exit 1
	}
	
	# Build complete arguments for both ROM and SRAM in single process
	$argsArray = @('-s', $luaScript, '-c', 'SNES', '-d', $cartDest)
	
	if ($hasSRAM -and $sramSizeKB -gt 0) {
		$argsArray += @('-a', $sramDest, '-w', "$sramSizeKB")
		Write-Host ""
		Write-Host "Parameters used (game ROM and save data):" -ForegroundColor Cyan
	} else {
		Write-Host ""
		Write-Host "Parameters used (only game ROM, no save data detected):" -ForegroundColor Cyan
	}

	$dumpSuccess = Invoke-INLRetro -ArgsArray $argsArray -CartDest $cartDest -SramDest $sramDest -HasSRAM $hasSRAM -CartridgeTitle $cartTitle -DetectionInfo $detectionInfo -CorrectVersion $correctVersion -PSScriptRoot $PSScriptRoot -TimesDumped $TimesDumped -LastArgsArray $LastArgsArray -LastCartDest $LastCartDest -LastSramDest $LastSramDest -LastHasSRAM $LastHasSRAM -BaseCartDest $BaseCartDest -BaseSramDest $BaseSramDest -LogFile $LogFile -SessionStartTime $SessionStartTime.Value

	if ($dumpSuccess) {
		# Display session timing message after successful dump
		Write-Host ""
		$sessionTimeFormatted = Format-SessionTime -StartTime $SessionStartTime.Value
		if ($sessionTimeFormatted -ne "") {
			Write-Host "====[ During this session, you have created $($TimesDumped.Value) cartridge dump(s) in $sessionTimeFormatted. ]====" -ForegroundColor DarkCyan
		}
		ReDump -LastArgsArray $LastArgsArray -BaseCartDest $BaseCartDest -BaseSramDest $BaseSramDest -LastHasSRAM $LastHasSRAM -TimesDumped $TimesDumped -BrowserPromptShown $BrowserPromptShown -PSScriptRoot $PSScriptRoot -LogFile $LogFile -SessionStartTime $SessionStartTime.Value -IgnoreDir $IgnoreDir
	} else {
		Write-Host "The dump failed. Please check the error messages above." -ForegroundColor Red
		Write-Host "Exiting due to failure." -ForegroundColor Red
		Show-LogFileLocation -TimesDumped $TimesDumped.Value -LogFile $LogFile
		Remove-IgnoreFolder -IgnoreDir $IgnoreDir
		exit 1
	}
}

Export-ModuleMember -Function Invoke-SNESDump

