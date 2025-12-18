# INLinterface.FileAnalysis.psm1
# Functions for analyzing file content and extracting cartridge information.
# This module provides file analysis capabilities for ROM and SRAM files, as well as cartridge header parsing.

# Module-specific constants (scoped to prevent export)
$script:SIGNATURE_BYTES = 16

<#
	Extracts cartridge information from header output.
	Parses the console output from cartridge detection to extract key information fields such as
	ROM title, map mode, hardware type, ROM size, SRAM size, expansion RAM size, destination code,
	developer, version, and checksum. Returns an array of formatted information strings in a
	specific order matching the console output. Handles special cases like version detection when
	header shows "0.0" by looking for firmware version information instead.
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
		"Version" = "(?:Version:\s*(.+?)(?:\r?\n|$)|firmware app ver request:\s+(\d+\.\d+\.\w+)|Device firmware version:\s+(\d+\.\d+\.\w+))"
		"Checksum" = "Checksum:\s*(.+?)(?:\r?\n|$)"
	}
	
	# Iterate in specified order to match console output
	foreach ($fieldName in $fieldOrder) {
		if ($fieldPatterns.ContainsKey($fieldName)) {
			$pattern = $fieldPatterns[$fieldName]
			if ($fieldName -eq "Version") {
				# Special handling for Version - prefer firmware version if header version is "0.0"
				$versionValue = $null
				$headerVersion = $null
				
				# First, try to get header version
				if ($HeaderOutput -match "Version:\s*(.+?)(?:\r?\n|$)") {
					$headerVersion = $matches[1].Trim()
				}
				
				# If header version is "0.0" or "0", look for firmware version or other version patterns
				if ($headerVersion -eq "0.0" -or $headerVersion -eq "0" -or -not $headerVersion) {
					# Check for firmware version patterns (more reliable when header shows 0.0)
					if ($HeaderOutput -match "firmware app ver request:\s+(\d+\.\d+\.\w+)") {
						$versionValue = $matches[1].Trim()
					} elseif ($HeaderOutput -match "Device firmware version:\s+(\d+\.\d+\.\w+)") {
						$versionValue = $matches[1].Trim()
					} elseif ($HeaderOutput -match "(\d+\.\d+\.\w+)" -and $matches[1] -match "^\d+\.\d+\.") {
						# Look for any version-like pattern (X.Y.Z format) in the output
						# This catches versions like "2.3.x" that might appear elsewhere
						$potentialVersion = $matches[1].Trim()
						# Only use if it looks like a version (not a checksum or other hex value)
						if ($potentialVersion -match "^\d+\.\d+\.") {
							$versionValue = $potentialVersion
						}
					}
					
					# If still no version found, fall back to header version
					if (-not $versionValue -and $headerVersion) {
						$versionValue = $headerVersion
					}
				} else {
					# Header version is valid, use it
					$versionValue = $headerVersion
				}
				
				if ($versionValue) {
					$paddedName = $fieldName.PadRight(23)
					$cartridgeInfo += "$paddedName $versionValue"
				}
			} else {
				if ($HeaderOutput -match $pattern) {
					$value = $matches[1].Trim()
					$paddedName = $fieldName.PadRight(23)
					$cartridgeInfo += "$paddedName $value"
				}
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
	Analyzes file content and returns analysis as text.
	Performs detailed analysis of ROM or SRAM files including file size, used/free space percentages,
	file signature (first 16 bytes), leading zero padding detection (ROM only), and validation checks.
	For SRAM files, also checks if the signature contains only zeros and warns if the file appears empty.
	Returns an array of analysis strings that can be displayed or logged.
#>
function Get-FileAnalysisText {
	param(
		[Parameter(Mandatory)]
		[string]$FilePath,
		
		[Parameter(Mandatory)]
		[string]$FileType,  # "ROM" or "SRAM"
		
		[int]$SignatureBytes = $script:SIGNATURE_BYTES
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
		if ($fileBytes.Length -ge $SignatureBytes) {
			$signature = $fileBytes[0..($SignatureBytes - 1)] | ForEach-Object { "{0:X2}" -f $_ }
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
	Displays file analysis lines with appropriate formatting.
	Takes an array of analysis text lines and displays them with color-coded formatting:
	- File size, used space, free space, and file signature lines use cyan labels with magenta values
	- Warning and note lines use dark yellow
	- Error messages use yellow
	- Empty lines are preserved for spacing
	Handles empty or null input gracefully by returning early.
#>
function Write-FileAnalysisLines {
	param(
		[Parameter(Mandatory=$false)]
		[string[]]$AnalysisLines
	)
	
	# Handle empty or null AnalysisLines
	if (-not $AnalysisLines -or $AnalysisLines.Count -eq 0) {
		return
	}
	
	foreach ($line in $AnalysisLines) {
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

Export-ModuleMember -Function Get-CartridgeInfo, Get-FileAnalysisText, Write-FileAnalysisLines

