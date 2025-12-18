# INLinterface.Dumping.psm1
# Main functions that handle the cartridge dumping process for different console types.
# This module orchestrates the dumping workflow for NES/Famicom and SNES cartridges.

<#
	Handles NES/Famicom cartridge dumping workflow.
	Guides the user through the NES/Famicom dumping process by prompting for mapper selection,
	PRG ROM size, CHR ROM presence and size, and SRAM/battery save presence. Constructs the
	appropriate command-line arguments for inlretro.exe and calls Invoke-INLRetro to execute
	the dump. Creates necessary output directories if they don't exist.
#>
function Invoke-NESBasedCartridgeDump {
	param(
		[Parameter(Mandatory)]
		[string]$ConsoleFolderName,
		
		[Parameter(Mandatory)]
		[string]$CartridgeName,
		
		[string]$PSScriptRoot,
		
		[string]$LogDir,
		
		[array]$NESmapperMenu,
		
		[int]$BrowserNesDelayMs,
		
		[ref]$TimesDumped,
		
		[ref]$LastArgsArray,
		
		[ref]$LastCartDest,
		
		[ref]$LastSramDest,
		
		[ref]$LastHasSRAM,
		
		[ref]$BaseCartDest,
		
		[ref]$BaseSramDest,
		
		[string]$LogFile,
		
		[DateTime]$SessionStartTime
	)
	
	$nesmap = Select-Mapper -CartridgeName $CartridgeName -NESmapperMenu $NESmapperMenu -BrowserNesDelayMs $BrowserNesDelayMs
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
	[void](New-Item -ItemType Directory -Path $LogDir -Force)

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

	$dumpSuccess = Invoke-INLRetro -ArgsArray $argsArray -CartDest $cartDest -SramDest $sramDest -HasSRAM $hasSRAM -CartridgeTitle "" -PSScriptRoot $PSScriptRoot -TimesDumped $TimesDumped -LastArgsArray $LastArgsArray -LastCartDest $LastCartDest -LastSramDest $LastSramDest -LastHasSRAM $LastHasSRAM -BaseCartDest $BaseCartDest -BaseSramDest $BaseSramDest -LogFile $LogFile -SessionStartTime $SessionStartTime
	
	return $dumpSuccess
}

<#
	Executes inlretro.exe with provided arguments and handles output.
	Runs the inlretro.exe executable with the specified arguments, capturing and displaying output
	in real-time. Handles version correction in output if a correct version is provided. Saves dump
	parameters for potential redump operations. After execution, analyzes the dumped ROM and SRAM
	files (if created), displays file analysis information, and logs the operation. Returns true
	on success, false on failure. Handles errors gracefully and provides user feedback.
#>
function Invoke-INLRetro {
	param(
		[string[]]$ArgsArray,
		[string]$CartDest,
		[string]$SramDest,
		[bool]$HasSRAM,
		[bool]$IsRedump = $false,
		[string]$CartridgeTitle = "",
		[string]$DetectionInfo = $null,
		[string]$CorrectVersion = $null,
		[string]$PSScriptRoot,
		[ref]$TimesDumped,
		[ref]$LastArgsArray,
		[ref]$LastCartDest,
		[ref]$LastSramDest,
		[ref]$LastHasSRAM,
		[ref]$BaseCartDest,
		[ref]$BaseSramDest,
		[string]$LogFile,
		[DateTime]$SessionStartTime
	)

	$exePath = Join-Path $PSScriptRoot 'inlretro.exe'
	
	# Check if executable exists
	if (-not (Test-Path $exePath)) {
		Write-Error "inlretro.exe not found at $exePath"
		return $false
	}
	
	# Save parameters for potential ReDump
	$LastArgsArray.Value = $ArgsArray
	$LastCartDest.Value = $CartDest
	$LastSramDest.Value = $SramDest
	$LastHasSRAM.Value = $HasSRAM
	
	# Save base filenames only if this is the first dump (no suffix in the name)
	if ($CartDest -notmatch '-dump\d+\.[^.]+$') {
		$BaseCartDest.Value = $CartDest
		$BaseSramDest.Value = $SramDest
	}

	# Format command string for display (convert absolute paths to relative)
	$formattedArgs = @()
	foreach ($arg in $ArgsArray) {
		# Check if this looks like a file path (starts with drive letter or is a long path)
		if ($arg -match '^[A-Za-z]:\\' -or $arg -match '^\\\\') {
			# Convert absolute path to relative path
			try {
				$arg = ConvertTo-RelativePath -Path $arg -ScriptRoot $PSScriptRoot
			} catch {
				# If conversion fails, use original path
			}
		}
		if ($arg -match '[\s"]') {
			$formattedArgs += '"' + ($arg -replace '"','`"') + '"'
		} else {
			$formattedArgs += $arg
		}
	}
	$pretty = $formattedArgs -join ' '

	# Only show command if not a redump
	if (-not $IsRedump) {
		Write-Host ".\inlretro.exe $pretty" -ForegroundColor DarkCyan
		Write-Host ""
	}

	# Execute with direct call operator to ensure real-time output display
	$exitCode = 0
	
	try {
		& $exePath @ArgsArray 2>&1 | ForEach-Object {
			$line = $_
			# Replace incorrect version in output if correct version is provided
			if ($CorrectVersion -and $line -match "^Version:\s+0\.0") {
				# Preserve the spacing format (tabs/spaces after "Version:")
				$line = $line -replace "Version:\s+0\.0", "Version:`t`t$CorrectVersion"
			}
			$line | Write-Host
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
			Write-DumpLog -CommandString $redumpMessage -CartridgeFile $CartDest -SramFile $SramDest -Success $false -DetectionInfo $DetectionInfo -CartridgeTitle $CartridgeTitle -TimesDumped $TimesDumped.Value -SessionStartTime $SessionStartTime -LogFile $LogFile
		} else {
			Write-DumpLog -CommandString $pretty -CartridgeFile $CartDest -SramFile $SramDest -Success $false -DetectionInfo $DetectionInfo -CartridgeTitle $CartridgeTitle -TimesDumped $TimesDumped.Value -SessionStartTime $SessionStartTime -LogFile $LogFile
		}
		
		return $false
	}
	
	if ($exitCode -eq 0) {
		$TimesDumped.Value++
		
		# Display console output for ROM/SRAM information immediately
		Write-Host "====[ Process Summary ]====" -ForegroundColor Cyan
		Write-Host ""
		$cartDestRelative = if (Get-Command ConvertTo-RelativePath -ErrorAction SilentlyContinue) {
			ConvertTo-RelativePath -Path $CartDest -ScriptRoot $PSScriptRoot
		} else {
			$CartDest
		}
		Write-Host "Cartridge game ROM location: " -NoNewline -ForegroundColor Cyan
		Write-Host "$cartDestRelative" -ForegroundColor Magenta
		
		# Get ROM file analysis (do this once, reuse for logging)
		$romAnalysis = @()
		$processSummary = @()
		if (Test-Path $CartDest) {
			$romAnalysis = @(Get-FileAnalysisText -FilePath $CartDest -FileType "ROM")
			$processSummary += "Cartridge game ROM location: $cartDestRelative"
			if ($romAnalysis.Count -gt 0) {
				$processSummary += $romAnalysis
			}
		}
		
		# Display cartridge ROM file analysis
		if ($romAnalysis.Count -gt 0) {
			Write-FileAnalysisLines -AnalysisLines $romAnalysis
		}
		
		# Check if SRAM file was actually created
		$sramAnalysis = @()
		if ($HasSRAM -and (Test-Path $SramDest)) {
			Write-Host ""
			$sramDestRelative = if (Get-Command ConvertTo-RelativePath -ErrorAction SilentlyContinue) {
				ConvertTo-RelativePath -Path $SramDest -ScriptRoot $PSScriptRoot
			} else {
				$SramDest
			}
			Write-Host "Cartridge save data location: " -NoNewline -ForegroundColor Cyan
			Write-Host "$sramDestRelative" -ForegroundColor Magenta
			
			# Get SRAM file analysis (do this once, reuse for logging)
			$sramAnalysis = @(Get-FileAnalysisText -FilePath $SramDest -FileType "SRAM")
			if ($processSummary.Count -gt 0) {
				$processSummary += ""  # Add blank line between ROM and SRAM analysis
			}
			$processSummary += "Cartridge save data location: $sramDestRelative"
			if ($sramAnalysis.Count -gt 0) {
				$processSummary += $sramAnalysis
			}
			
			# Display SRAM file analysis
			Write-FileAnalysisLines -AnalysisLines $sramAnalysis
			
		} elseif ($HasSRAM -and -not (Test-Path $SramDest)) {
			# PowerShell detected SRAM but Lua script determined no SRAM file should be created
			Write-Host "No save data found, the cartridge does not have SRAM or the battery is dead." -ForegroundColor Yellow
			Write-Host "The LUA script correctly determined this cartridge has no usable save RAM." -ForegroundColor Cyan
			Write-Host ""
		}
		
		# Log successful dump (after display, using already-computed analysis)
		if ($IsRedump) {
			$redumpMessage = "Re-running previous cartridge dump command. Subsequent dump attempts are saved with incrementing identifiers appended to the output file name."
			Write-DumpLog -CommandString $redumpMessage -CartridgeFile $CartDest -SramFile $SramDest -Success $true -DetectionInfo $DetectionInfo -IsRedump $true -CartridgeTitle $CartridgeTitle -ProcessSummary ($processSummary -join "`n") -TimesDumped $TimesDumped.Value -SessionStartTime $SessionStartTime -LogFile $LogFile
		} else {
			Write-DumpLog -CommandString $pretty -CartridgeFile $CartDest -SramFile $SramDest -Success $true -DetectionInfo $DetectionInfo -IsRedump $false -CartridgeTitle $CartridgeTitle -ProcessSummary ($processSummary -join "`n") -TimesDumped $TimesDumped.Value -SessionStartTime $SessionStartTime -LogFile $LogFile
		}
		
		return $true
	}
}

<#
	Handles redump functionality - allows multiple dump attempts.
	Enables users to perform multiple dump attempts of the same cartridge with incrementing file
	suffixes (-dump1, -dump2, etc.). Prompts for cleaning instructions and optionally opens a
	cleaning guide URL (first time only). For each redump, modifies the file paths in the saved
	arguments array to add the incrementing suffix. After successful redumps, prompts whether to
	dump another cartridge or exit. Continues until user chooses not to redump or chooses to exit.
#>
function ReDump {
	param(
		[ref]$LastArgsArray,
		[ref]$BaseCartDest,
		[ref]$BaseSramDest,
		[ref]$LastHasSRAM,
		[ref]$TimesDumped,
		[ref]$BrowserPromptShown,
		[string]$PSScriptRoot,
		[string]$LogFile,
		[DateTime]$SessionStartTime,
		[string]$IgnoreDir
	)
	
	# Check if parameters from a previous dump exist
	if ($null -eq $LastArgsArray.Value) {
		return  # No previous dump to redo
	}

	# Redumping will continue until the choice is 'n'
	while ($true) {
		Write-Host ""
		Write-Host "If the ROM is not working as expected, reseat or clean cartridge contacts before reattempting."
		Write-Host "WHEN CLEANING: NEVER USE BRASSO!" -ForegroundColor Red
		Write-Host ""
		
		# Display cleaning instructions with option to open URL (only first time)
		if (-not $BrowserPromptShown.Value) {
			$openLink = Read-YesNo "Would you like to access the RetroRGB.com article on cleaning best practices?"
			if ($openLink) {
				Open-UrlInDefaultBrowser-AndReturn -Url "https://www.retrorgb.com/cleangames.html"
			}
		
			$BrowserPromptShown.Value = $true
		}
		
		$rerun = Read-YesNo "Proceed with another attempt? (An incremental version will be made.)"
		
		if ($rerun) {
			Write-Host ""
			Write-Host "====[ Performing cartridge redump ]====" -ForegroundColor DarkCyan
			
			$suffix = "-dump$($TimesDumped.Value)"
			
			# Use the BASE filenames (without any existing suffixes)
			$newCartDest = $BaseCartDest.Value -replace '(\.[^.]+)$', "$suffix`$1"
			$newSramDest = $BaseSramDest.Value -replace '(\.[^.]+)$', "$suffix`$1"
			
			# Modify the file paths in the args array
			$newArgsArray = $LastArgsArray.Value.Clone()
			for ($i = 0; $i -lt $newArgsArray.Count; $i++) {
				if ($newArgsArray[$i] -eq '-d' -and $i + 1 -lt $newArgsArray.Count) {
					$newArgsArray[$i + 1] = $newCartDest
				}
				if ($newArgsArray[$i] -eq '-a' -and $i + 1 -lt $newArgsArray.Count) {
					$newArgsArray[$i + 1] = $newSramDest
				}
			}
			
			$redumpSuccess = Invoke-INLRetro -ArgsArray $newArgsArray -CartDest $newCartDest -SramDest $newSramDest -HasSRAM $LastHasSRAM.Value -IsRedump $true -CartridgeTitle "" -PSScriptRoot $PSScriptRoot -TimesDumped $TimesDumped -LastArgsArray $LastArgsArray -LastCartDest ([ref]$newCartDest) -LastSramDest ([ref]$newSramDest) -LastHasSRAM $LastHasSRAM -BaseCartDest $BaseCartDest -BaseSramDest $BaseSramDest -LogFile $LogFile -SessionStartTime $SessionStartTime
			
			if (-not $redumpSuccess) {
				Write-Host ""
				Write-Host "Redump attempt failed. Exiting application." -ForegroundColor Red
				Show-LogFileLocation -TimesDumped $TimesDumped.Value -LogFile $LogFile
				Remove-IgnoreFolder -IgnoreDir $IgnoreDir
				exit 1
			}
			
			# Display session timing message after successful redump
			Write-Host ""
			$sessionTimeFormatted = Format-SessionTime -StartTime $SessionStartTime
			if ($sessionTimeFormatted -ne "") {
				Write-Host "====[ During this session, you have created $($TimesDumped.Value) cartridge dump(s) in $sessionTimeFormatted. ]====" -ForegroundColor DarkCyan
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
				Show-LogFileLocation -TimesDumped $TimesDumped.Value -LogFile $LogFile
				Write-Host "Exiting INL Retro Dumper Interface. Goodbye!" -ForegroundColor DarkCyan
				Remove-IgnoreFolder -IgnoreDir $IgnoreDir
				exit 0
			}
		}
	}
	
	return $true
}

Export-ModuleMember -Function Invoke-NESBasedCartridgeDump, Invoke-INLRetro, ReDump

