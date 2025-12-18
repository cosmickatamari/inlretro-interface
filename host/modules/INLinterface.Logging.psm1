# INLinterface.Logging.psm1
# Functions for writing detailed operation logs and formatted output.
# This module handles logging operations for cartridge dump sessions.

<#
	Writes dump operation information to log file.
	Creates a detailed log entry for each cartridge dump operation including timestamp, command parameters,
	detection information, cartridge info, process summary (file locations and analysis), session timing,
	and success/failure status. Formats detection messages with proper indentation and handles special
	cases like cartridge info sections and process summaries. Log entries are appended to the session log file.
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
		
		[string]$ProcessSummary = $null,
		
		[int]$TimesDumped,
		
		[DateTime]$SessionStartTime,
		
		[string]$LogFile
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
====[ Cartridge $TimesDumped$redumpText$cartridgeNameText processed $timestamp ]====

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
		
		$previousLineWasDetectionMessage = $false
		foreach ($line in $detectionLines) {
			if ($line.Trim() -ne "") {
				# Check if this is a section header (Cartridge Info:)
				if ($line -match "^Cartridge Info:$") {
					$inCartridgeInfoSection = $true
					# Add blank line before Cartridge Info if previous non-empty line was a detection message
					if ($previousLineWasDetectionMessage) {
						# Check if logEntry already ends with blank line (two newlines)
						if ($logEntry -match "`n`n$") {
							# Already has blank line, just add the line
							$logEntry += "$line"
						} elseif ($logEntry -match "`n$") {
							# Ends with single newline, add one more for blank line
							$logEntry += "`n$line"
						} else {
							# Doesn't end with newline, add two for blank line
							$logEntry += "`n`n$line"
						}
					} else {
						# No blank line needed, just ensure single line break
						if ($logEntry -match "`n$") {
							$logEntry += "$line"
						} else {
							$logEntry += "`n$line"
						}
					}
					$previousLineWasDetectionMessage = $false
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
					$previousLineWasDetectionMessage = $false
				}
				# Check if this is a final status message - don't indent these
				elseif ($line -match "^Final SRAM detection status:" -or $line -match "^SRAM detected.*will dump") {
					$logEntry += "`n$line"
					$previousLineWasDetectionMessage = $true
				} else {
					# Indent content under steps
					$logEntry += "`n>> $line"
					$previousLineWasDetectionMessage = $true
				}
			} else {
				# Empty line - don't reset detection message flag (preserve it across empty lines)
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
	$sessionTimeFormatted = Format-SessionTime -StartTime $SessionStartTime
	if ($sessionTimeFormatted -ne "") {
		# Add line break before session time for redumps (after file signature)
		if ($IsRedump) {
			$logEntry += "`n"
		}
		$logEntry += "`nSession Time: $sessionTimeFormatted"
	}
	
	$logEntry += "`nStatus: $(if($Success) { 'Great Success!' } else { 'Failure.' })"
	# Separator with dashes (same length as original -+-+ pattern: 89 characters)
	$separator = "-" * 89
	$logEntry += "`n`n$separator`n"
	
	# Write to log file efficiently
	try {
		$logEntry | Out-File -FilePath $LogFile -Append -Encoding UTF8
	} catch {
		Write-Warning "Failed to write to log file: $($_.Exception.Message)"
	}
}

Export-ModuleMember -Function Write-DumpLog

