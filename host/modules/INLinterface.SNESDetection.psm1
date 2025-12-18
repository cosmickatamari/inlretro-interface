# INLinterface.SNESDetection.psm1
# Functions for detecting SRAM (Save RAM) configuration from SNES cartridge headers and runtime output.
# This module handles the multi-step SRAM detection process for SNES cartridges.

# Module-specific constants (scoped to prevent export)
$script:SUPERFX_SRAM_SIZE_KB = 32
$script:DEFAULT_SRAM_SIZE_KB = 8
$script:DETECTION_PROGRESS_INTERVAL_MS = 100
$script:COMPLETION_MSG_PAD_LENGTH = 80

<#
	Runs cartridge detection process and captures output.
	Executes the inlretro.exe detection command with temporary output files in the ignore folder.
	Displays progress messages showing elapsed time during detection. Captures both standard output
	and error output, combines them, and returns the complete detection output. Cleans up temporary
	files after reading. Sets the session start time for timing calculations.
#>
function Invoke-CartridgeDetection {
	param(
		[Parameter(Mandatory)]
		[string]$TestExePath,
		
		[Parameter(Mandatory)]
		[string[]]$TestArgs,
		
		[string]$IgnoreDir,
		
		[ref]$SessionStartTime
	)
	
	# Initialize ignore folder for temporary detection files
	Initialize-IgnoreFolder -IgnoreDir $IgnoreDir
	
	$headerOutput = ""
	$counter = 0
	$detectionStartTime = Get-Date
	$SessionStartTime.Value = Get-Date  # Set session timer at start of detection
	
	# Use paths within the ignore folder for temporary files
	$tempOutputPath = Join-Path $IgnoreDir "temp_detection_output.txt"
	$tempErrorPath = Join-Path $IgnoreDir "temp_detection_error.txt"
	
	# Start the process and read output line by line
	$process = Start-Process -FilePath $TestExePath -ArgumentList $TestArgs -NoNewWindow -PassThru -RedirectStandardOutput $tempOutputPath -RedirectStandardError $tempErrorPath
	
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
	if (Test-Path $tempOutputPath) {
		$headerOutput = Get-Content $tempOutputPath -Raw
		Remove-Item $tempOutputPath -Force
	}
	if (Test-Path $tempErrorPath) {
		$errorOutput = Get-Content $tempErrorPath -Raw
		if ($errorOutput -and $errorOutput.Trim().Length -gt 0) {
			$headerOutput += $errorOutput
		}
		Remove-Item $tempErrorPath -Force
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
	Detects SRAM size from header (Step 1).
	Checks the cartridge header output for SRAM Size field in either KB format or kilobits format.
	If found and greater than 0, sets the hasSRAM flag and sramSizeKB value. Converts kilobits to KB
	if necessary. Writes detection messages to the output and detection messages array. Returns true
	if SRAM size was found in the header, false otherwise.
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
	Detects SRAM from runtime messages (Step 2).
	Checks the detection output for runtime messages indicating Save RAM Size detection. Only runs
	if Step 1 did not find SRAM size in the header (can be skipped if header already found size).
	If Save RAM Size is detected and greater than 0, sets hasSRAM and sramSizeKB. If size is 0,
	explicitly sets hasSRAM to false. Writes detection messages to output and detection messages array.
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
	Checks SRAM table size override.
	Looks for "Using SRAM table size" messages in the detection output, which indicate a corrected
	SRAM size from the SRAM table that overrides the header size. This check always runs regardless
	of previous steps because table sizes take precedence. If found and greater than 0, updates
	hasSRAM and sramSizeKB with the corrected values.
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
	Detects SRAM from hardware type (Step 3).
	Checks if the Hardware Type field contains "Save RAM" indication. If found and SRAM hasn't been
	detected yet, sets hasSRAM and determines the size. For SuperFX games with Save RAM, uses the
	SuperFX SRAM size constant (32KB). For other games, uses the default SRAM size (8KB). If SRAM
	was already detected but size is still 0, attempts to determine size based on hardware type.
	Only reports absence if SRAM hasn't been confirmed yet. Writes detection messages to output.
#>
function Test-SRAMHardwareType {
	param(
		[Parameter(Mandatory)]
		[string]$HeaderOutput,
		
		[ref]$HasSRAM,
		
		[ref]$SramSizeKB,
		
		[ref]$DetectionMessages,
		
		[int]$SuperFxSramSizeKB = $script:SUPERFX_SRAM_SIZE_KB,
		
		[int]$DefaultSramSizeKB = $script:DEFAULT_SRAM_SIZE_KB
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
				$SramSizeKB.Value = $SuperFxSramSizeKB
				$superFxMsg = "SuperFX game with Save RAM detected - setting ${SuperFxSramSizeKB}KB default."
				Write-Host $superFxMsg -ForegroundColor Green
				$DetectionMessages.Value += $superFxMsg
			} else {
				$HasSRAM.Value = $true
				$SramSizeKB.Value = $DefaultSramSizeKB
				$hwTypeMsg = "Hardware Type indicates Save RAM - setting hasSRAM = true, size will be auto-detected."
				Write-Host $hwTypeMsg -ForegroundColor Green
				$DetectionMessages.Value += $hwTypeMsg
			}
		} elseif ($HasSRAM.Value -and $SramSizeKB.Value -eq 0) {
			# SRAM was detected but size is still 0 - need to determine size
			if ($HeaderOutput -match "Hardware Type:.*SuperFX.*Save RAM") {
				$SramSizeKB.Value = $SuperFxSramSizeKB
				$superFxMsg = "SuperFX game with Save RAM detected - setting ${SuperFxSramSizeKB}KB size."
				Write-Host $superFxMsg -ForegroundColor Green
				$DetectionMessages.Value += $superFxMsg
			} else {
				$SramSizeKB.Value = $DefaultSramSizeKB
				$hwTypeMsg = "Hardware Type indicates Save RAM - setting ${DefaultSramSizeKB}KB default."
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
	Detects SuperFX SRAM from expansion RAM field (Step 4).
	Special detection step for SuperFX games where SRAM size may be stored in the Expansion RAM Size
	field instead of the SRAM Size field. Only runs for SuperFX games that have "Save RAM" in hardware
	type but "SRAM Size: None" in the header. Converts Expansion RAM Size from kilobits to KB and sets
	hasSRAM and sramSizeKB accordingly. This handles edge cases like Stunt Race FX. Only adds output
	messages if Step 4 actually runs (silently skips otherwise).
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
	# Only check if we haven't found SRAM yet AND this is a SuperFX game
	# Step 4 is only needed for edge cases where SuperFX games have SRAM Size = None
	# but the actual SRAM size is stored in Expansion RAM Size field (e.g., Stunt Race FX)
	$step4Ran = $false
	if ($HeaderOutput -match "Hardware Type:.*SuperFX") {
		# Only proceed if SRAM hasn't been detected yet
		if (-not ($HasSRAM.Value -and $SramSizeKB.Value -gt 0)) {
			if ($HeaderOutput -match "Hardware Type:.*SuperFX.*Save RAM" -and $HeaderOutput -match "SRAM Size:\s*None") {
				$step4Ran = $true
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
				} else {
					# SuperFX game with Save RAM but no Expansion RAM Size found
					$noExpRamMsg = "SuperFX game detected but Expansion RAM Size not found."
					Write-Host $noExpRamMsg -ForegroundColor Yellow
					$DetectionMessages.Value += $noExpRamMsg
				}
			}
			# If SuperFX game but SRAM Size is not "None", it was already detected in earlier steps - no message needed
		}
		# If SRAM already detected, Step 4 is not needed - silently skip
	}
	# If not a SuperFX game, Step 4 doesn't apply - silently skip (no message needed)
	
	# Only add blank line if Step 4 actually ran
	if ($step4Ran) {
		Write-Host ""
		$DetectionMessages.Value += ""
	}
}

<#
	Performs complete SRAM detection for SNES cartridges.
	Orchestrates the multi-step SRAM detection process by calling each detection step in sequence:
	Step 1: Check header for SRAM Size
	Step 2: Check runtime detection messages (if Step 1 didn't find size)
	SRAM table size override check (always runs)
	Step 3: Check Hardware Type for Save RAM indication
	Step 4: Check SuperFX Expansion RAM field (if applicable)
	Ensures hasSRAM is false if size is 0. Returns a hashtable containing hasSRAM flag, sramSizeKB value,
	and detectionMessages array. Handles errors gracefully by assuming no SRAM exists if detection fails.
#>
function Invoke-SNESSRAMDetection {
	param(
		[Parameter(Mandatory)]
		[string]$HeaderOutput,
		
		[int]$SuperFxSramSizeKB = $script:SUPERFX_SRAM_SIZE_KB,
		
		[int]$DefaultSramSizeKB = $script:DEFAULT_SRAM_SIZE_KB
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
		Test-SRAMHardwareType -HeaderOutput $HeaderOutput -HasSRAM ([ref]$hasSRAM) -SramSizeKB ([ref]$sramSizeKB) -DetectionMessages ([ref]$detectionMessages) -SuperFxSramSizeKB $SuperFxSramSizeKB -DefaultSramSizeKB $DefaultSramSizeKB
		
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

Export-ModuleMember -Function Invoke-CartridgeDetection, Test-SRAMHeader, Test-SRAMRuntime, Test-SRAMTableSize, Test-SRAMHardwareType, Test-SuperFXExpansionRAM, Invoke-SNESSRAMDetection

