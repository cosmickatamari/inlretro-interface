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
	Formats elapsed session time from a start DateTime.
	- Under 60 minutes: "Xm Ys" or "Xs"
	- 60 minutes up to 24 hours: "Xh Ym Zs"
	- 24 hours or more: "N day(s), Xh Ym Zs"
	Returns an empty string if the start time is null.
#>
function Format-SessionTime {
	param([DateTime]$StartTime)
	
	if ($null -eq $StartTime) { return "" }
	
	$e = (Get-Date) - $StartTime
	if ($e.TotalSeconds -lt 0) { return "0s" }
	
	$d = $e.Days
	$h = $e.Hours
	$m = $e.Minutes
	$s = $e.Seconds
	
	if ($e.TotalHours -ge 24) {
		$dayWord = if ($d -eq 1) { 'day' } else { 'days' }
		return "${d} ${dayWord}, ${h}h ${m}m ${s}s"
	}
	if ($e.TotalMinutes -ge 60) {
		return "${h}h ${m}m ${s}s"
	}
	if ($m -gt 0) {
		return "${m}m ${s}s"
	}
	return "${s}s"
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

# Not exported: ROM bank progress row. Do not emit raw CSI via Console.Out — integrated terminals
# often print ESC as visible "←["; Write-Host uses the host palette (explicit colors, no escape bytes).
function Write-INLRomBankVtLine {
	param(
		[Parameter(Mandatory)][string]$LabelCol,
		[Parameter(Mandatory)][string]$ValueText
	)
	Write-Host $LabelCol -NoNewline -ForegroundColor White
	Write-Host $ValueText -ForegroundColor DarkCyan
}

<#
	Writes one line that may contain inlretro/Lua SGR sequences (\e[Nm with N in 0,33,36,37,96).
	Uses Write-Host segments so colors work in integrated terminals (Cursor/VS Code) where
	raw ESC bytes are shown literally even when Win32 VT is enabled.
#>
function Write-INLHostAnsiLine {
	param(
		[Parameter(Mandatory = $false)]
		[AllowEmptyString()]
		[string]$Line
	)
	if ($null -eq $Line) { $Line = '' }
	$Line = [string]$Line
	$esc = [char]0x1B
	$csi = [char]0x9B
	# Lua emits INL-ROM-BANK\tcurrent\tlast under INLRETRO_INTERFACE=1 (Invoke-INLRetro always sets it).
	$probeInl = [regex]::Replace($Line, '(?:\x1B|\x9B)\[[0-9;]*m', '').TrimEnd("`r").TrimStart([char]0xFEFF).Trim()
	if ($probeInl -cmatch 'INL-ROM-BANK\t(\d+)\t(\d+)') {
		$romLbl = 'Dumping ROM bank:'.PadRight(30)
		$romVal = "$($matches[1]) of $($matches[2])"
		Write-INLRomBankVtLine -LabelCol $romLbl -ValueText $romVal
		return
	}
	# Rare: some capture/display paths replace ESC with U+2190 (←); normalize for parsing.
	$arrow = [char]0x2190
	if ($Line.IndexOf($esc) -lt 0 -and $Line.IndexOf($arrow) -ge 0) {
		$Line = $Line.Replace("$arrow[", "$esc[")
	}
	# Fallback: human-readable ROM bank line (older Lua or manual runs).
	$plainRom = [regex]::Replace($Line, '(?:\x1B|\x9B)\[[0-9;]*m', '')
	$plainRom = $plainRom.TrimEnd("`r")
	$plainTrim = $plainRom.TrimStart([char]0xFEFF).TrimStart()
	$bankNeedle = 'Dumping ROM bank:'
	$bankPos = $plainTrim.IndexOf($bankNeedle, [System.StringComparison]::Ordinal)
	if ($bankPos -ge 0) {
		$plainBank = $plainTrim.Substring($bankPos).TrimEnd()
		$bankM = [regex]::Match($plainBank, '^Dumping ROM bank:(\s*)(\d+ of \d+)\s*$')
		if ($bankM.Success) {
			$romBankLbl = ('Dumping ROM bank:' + $bankM.Groups[1].Value)
			if ($romBankLbl.Length -lt 30) {
				$romBankLbl = $romBankLbl.PadRight(30)
			} elseif ($romBankLbl.Length -gt 30) {
				$romBankLbl = $romBankLbl.Substring(0, 30)
			}
			$romBankVal = $bankM.Groups[2].Value
			Write-INLRomBankVtLine -LabelCol $romBankLbl -ValueText $romBankVal
			return
		}
	}
	if ($Line.IndexOf($esc) -lt 0 -and $Line.IndexOf($csi) -lt 0) {
		Write-Host $Line
		return
	}

	$pattern = [regex]::new([regex]::Escape($esc) + '\[([0-9;]*)m')
	$idx = 0
	$fc = $null
	foreach ($m in $pattern.Matches($Line)) {
		if ($m.Index -gt $idx) {
			$chunk = $Line.Substring($idx, $m.Index - $idx)
			if ($chunk.Length -gt 0) {
				if ($null -ne $fc) {
					Write-Host $chunk -NoNewline -ForegroundColor $fc
				} else {
					Write-Host $chunk -NoNewline
				}
			}
		}
		foreach ($part in ($m.Groups[1].Value -split ';')) {
			$p = $part.Trim()
			if ($p -eq '' -or $p -eq '1') { continue }
			switch ($p) {
				'0' { $fc = $null }
				'33' { $fc = 'Yellow' }
				'36' { $fc = 'DarkCyan' }
				'37' { $fc = 'White' }
				'96' { $fc = 'Cyan' }
				Default { }
			}
		}
		$idx = $m.Index + $m.Length
	}
	if ($idx -lt $Line.Length) {
		$chunk = $Line.Substring($idx)
		if ($chunk.Length -gt 0) {
			if ($null -ne $fc) {
				Write-Host $chunk -NoNewline -ForegroundColor $fc
			} else {
				Write-Host $chunk -NoNewline
			}
		}
	}
	Write-Host ''
}

<#
	Session banner after a dump: static prose cyan; dump count and elapsed time dark cyan.
	Called only from Invoke-INLRetro (all console paths and redumps funnel through it).
#>
function Write-INLSessionDumpCountBanner {
	param(
		[Parameter(Mandatory)][int]$DumpCount,
		[Parameter(Mandatory)][AllowEmptyString()][string]$SessionTimeFormatted
	)
	if ([string]::IsNullOrWhiteSpace($SessionTimeFormatted)) {
		return
	}
	Write-Host '====[ During this session, you have created ' -NoNewline -ForegroundColor Cyan
	Write-Host "$DumpCount" -NoNewline -ForegroundColor DarkCyan
	Write-Host ' cartridge dump(s) in ' -NoNewline -ForegroundColor Cyan
	Write-Host $SessionTimeFormatted -NoNewline -ForegroundColor DarkCyan
	Write-Host '. ]====' -ForegroundColor Cyan
}

<#
	Enables Windows console virtual-terminal processing (ANSI escape interpretation) on the
	current process stdout/stderr handles. Required when child process output is captured and
	re-printed: without this, sequences like ESC[36m show as visible garbage (←[36m).
	No-op on non-Windows or if the process has no console (e.g. pure redirection).
#>
function Enable-INLConsoleVirtualTerminal {
	if (-not ($IsWindows -or $PSVersionTable.Platform -eq 'Win32NT')) {
		return
	}
	try {
		if (-not ('INLConsoleVt' -as [type])) {
			Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class INLConsoleVt {
	[DllImport("kernel32.dll", SetLastError = true)]
	public static extern IntPtr GetStdHandle(int nStdHandle);
	[DllImport("kernel32.dll", SetLastError = true)]
	public static extern bool GetConsoleMode(IntPtr h, out uint mode);
	[DllImport("kernel32.dll", SetLastError = true)]
	public static extern bool SetConsoleMode(IntPtr h, uint mode);
	public const int STD_OUTPUT_HANDLE = -11;
	public const int STD_ERROR_HANDLE = -12;
	public const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
	public static void TryEnableOutAndErr() {
		foreach (int std in new int[] { STD_OUTPUT_HANDLE, STD_ERROR_HANDLE }) {
			IntPtr h = GetStdHandle(std);
			if (h == IntPtr.Zero || h == new IntPtr(-1)) continue;
			if (!GetConsoleMode(h, out uint mode)) continue;
			SetConsoleMode(h, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
		}
	}
}
'@ -ErrorAction Stop
		}
		[INLConsoleVt]::TryEnableOutAndErr()
	} catch {
		# Ignore: non-console host, older Windows, or security-restricted environments
	}
}

Export-ModuleMember -Function 'Initialize-IgnoreFolder', 'Remove-IgnoreFolder', 'Read-YesNo', 'Read-Int', 'Read-KB-MultipleOf4', 'Format-SessionTime', 'ConvertTo-SafeFileName', 'ConvertTo-RelativePath', 'Write-INLHostAnsiLine', 'Write-INLSessionDumpCountBanner', 'Enable-INLConsoleVirtualTerminal'

