# INLinterface.Utility.psm1
# Utility functions for common operations used throughout the INL Retro Dumper Interface.
# This module provides basic utility functions for user input, file operations, and time formatting.

<#
	Initializes the ignore folder for temporary detection files.
	This folder is used to store temporary files created during cartridge detection
	and is cleaned up after the detection process completes.
#>
function Initialize-IgnoreFolder {
	param([string]$IgnoreDir)
	
	if (-not (Test-Path $IgnoreDir)) {
		[void](New-Item -ItemType Directory -Path $IgnoreDir -Force)
	}
}

<#
	Cleans up the ignore folder by removing it and all contents.
	This function is called at script exit to ensure temporary files are removed.
	Errors during cleanup are silently ignored to prevent script termination.
#>
function Remove-IgnoreFolder {
	param([string]$IgnoreDir)
	
	if (Test-Path $IgnoreDir) {
		try {
			Remove-Item -Path $IgnoreDir -Recurse -Force -ErrorAction SilentlyContinue
		} catch {
			# Silently continue if cleanup fails
		}
	}
}

<#
	Reads yes/no input from user with validation.
	Prompts the user with a custom message and validates the input, defaulting to 'n' (no) if the user
	presses Enter without entering a value. Continues prompting until valid input (y, n, or Enter) is received.
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
	Reads integer input from user with range validation.
	Prompts the user for an integer value and validates it against optional minimum and maximum bounds.
	Continues prompting until a valid integer within the specified range is entered.
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
	Reads KB value that is a multiple of 4, starting from 8.
	Used for ROM size inputs where values must be in increments of 4KB (8KB, 12KB, 16KB, etc.).
	Continues prompting until a valid value meeting these criteria is entered.
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
	Formats elapsed time as human-readable string.
	Converts a DateTime start time into a formatted string showing minutes and seconds elapsed.
	Returns an empty string if the start time is null.
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
	Converts cartridge name to Windows-safe filename.
	Replaces invalid Windows filename characters (< > : " / \ | ? *) with safe alternatives.
	Invalid characters are replaced with " - " (space-dash-space), and other problematic characters
	are removed. Extra spaces are trimmed and normalized. Returns a filename-safe string that can
	be used for creating output files.
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
	Converts absolute paths to relative paths from the script root.
	Takes a full path and the script root directory, and returns a path relative to the script root.
	If the path is within the script root, returns the relative path with a leading backslash.
	If the path is outside the script root, returns the original path unchanged.
#>
function ConvertTo-RelativePath {
	param(
		[Parameter(Mandatory)]
		[string]$Path,
		
		[Parameter(Mandatory)]
		[string]$ScriptRoot
	)
	
	# Normalize paths for comparison
	$normalizedPath = [System.IO.Path]::GetFullPath($Path)
	$normalizedRoot = [System.IO.Path]::GetFullPath($ScriptRoot)
	
	# Check if path is within script root
	if ($normalizedPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
		# Get relative path
		$relativePath = $normalizedPath.Substring($normalizedRoot.Length)
		# Ensure leading dot-backslash (.\)
		if (-not $relativePath.StartsWith('\')) {
			$relativePath = '.\' + $relativePath
		} else {
			# Replace leading backslash with dot-backslash
			$relativePath = '.' + $relativePath
		}
		# Normalize backslashes
		$relativePath = $relativePath.Replace('\', '\')
		return $relativePath
	}
	
	# Path is outside script root, return as-is
	return $Path
}

Export-ModuleMember -Function 'Initialize-IgnoreFolder', 'Remove-IgnoreFolder', 'Read-YesNo', 'Read-Int', 'Read-KB-MultipleOf4', 'Format-SessionTime', 'ConvertTo-SafeFileName', 'ConvertTo-RelativePath'

