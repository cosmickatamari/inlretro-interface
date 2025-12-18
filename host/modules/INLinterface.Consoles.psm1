# INLinterface.Consoles.psm1
# Console-specific dumping workflow routing with dynamic module loading.
# This module routes console selection to the appropriate console-specific module, loading it on-demand.

<#
	Handles console-specific dumping workflow routing with dynamic module loading.
	Takes the selected console name and dynamically loads the appropriate console module,
	then routes to the console-specific dumping function. Only loads the module when needed.
	Returns true on success, false on failure, or exits the application on critical errors.
#>
function Invoke-ConsoleDump {
	param(
		[Parameter(Mandatory)]
		[string]$ConsoleName,
		
		[Parameter(Mandatory)]
		[string]$CartridgeName,
		
		[string]$PSScriptRoot,
		
		[string]$LogDir,
		
		[string]$IgnoreDir,
		
		[string]$LogFile,
		
		[array]$NESmapperMenu,
		
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
	
	# Map console names to their module file names and function names
	$consoleModules = @{
		'Nintendo Entertainment System' = @{
			Module = 'INLinterface.Console.NES.psm1'
			Function = 'Invoke-NESDump'
		}
		'Nintendo Famicom (Family Computer)' = @{
			Module = 'INLinterface.Console.Famicom.psm1'
			Function = 'Invoke-FamicomDump'
		}
		'Super Nintendo Entertainment System' = @{
			Module = 'INLinterface.Console.SNES.psm1'
			Function = 'Invoke-SNESDump'
		}
		'Nintendo 64' = @{
			Module = 'INLinterface.Console.N64.psm1'
			Function = 'Invoke-N64Dump'
		}
		'Gameboy / Gameboy Advance' = @{
			Module = 'INLinterface.Console.Gameboy.psm1'
			Function = 'Invoke-GameboyDump'
		}
		'Sega Genesis' = @{
			Module = 'INLinterface.Console.Genesis.psm1'
			Function = 'Invoke-GenesisDump'
		}
	}
	
	# Check if console is supported
	if (-not $consoleModules.ContainsKey($ConsoleName)) {
		Write-Host "Unknown console: $ConsoleName" -ForegroundColor Red
		return $false
	}
	
	# Get module information
	$moduleInfo = $consoleModules[$ConsoleName]
	$modulePath = Join-Path $PSScriptRoot "modules\$($moduleInfo.Module)"
	
	# Dynamically import the console-specific module
	try {
		Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop
	} catch {
		Write-Error "Failed to load console module: $($moduleInfo.Module)"
		Write-Error "Error: $($_.Exception.Message)"
		return $false
	}
	
	# Build parameter hashtable for the console dump function
	$dumpParams = @{
		CartridgeName = $CartridgeName
		PSScriptRoot = $PSScriptRoot
		LogDir = $LogDir
		IgnoreDir = $IgnoreDir
		LogFile = $LogFile
		TimesDumped = $TimesDumped
		LastArgsArray = $LastArgsArray
		LastCartDest = $LastCartDest
		LastSramDest = $LastSramDest
		LastHasSRAM = $LastHasSRAM
		BaseCartDest = $BaseCartDest
		BaseSramDest = $BaseSramDest
		BrowserPromptShown = $BrowserPromptShown
		SessionStartTime = $SessionStartTime
	}
	
	# Add NESmapperMenu parameter only for NES/Famicom consoles
	if ($ConsoleName -eq 'Nintendo Entertainment System' -or $ConsoleName -eq 'Nintendo Famicom (Family Computer)') {
		$dumpParams['NESmapperMenu'] = $NESmapperMenu
	}
	
	# Call the console-specific dump function
	& $moduleInfo.Function @dumpParams
	
	return $true
}

Export-ModuleMember -Function Invoke-ConsoleDump

