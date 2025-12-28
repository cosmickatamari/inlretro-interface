# INLinterface.Console.NES.psm1
# Nintendo Entertainment System console-specific dumping workflow.
# This module handles the complete NES cartridge dumping process.

<#
	Handles Nintendo Entertainment System cartridge dumping workflow.
	Guides the user through the NES dumping process, executes the dump, and handles post-dump operations.
	Returns true on success, false on failure, or exits the application on critical errors.
#>
function Invoke-NESDump {
	param(
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
	
	# Initialize SessionStartTime if it hasn't been set yet (for timing calculations)
	if ($null -eq $SessionStartTime.Value) {
		$SessionStartTime.Value = Get-Date
	}
	
	$dumpSuccess = Invoke-NESBasedCartridgeDump -ConsoleFolderName 'nes' -CartridgeName $CartridgeName -PSScriptRoot $PSScriptRoot -LogDir $LogDir -NESmapperMenu $NESmapperMenu -BrowserNesDelayMs 750 -TimesDumped $TimesDumped -LastArgsArray $LastArgsArray -LastCartDest $LastCartDest -LastSramDest $LastSramDest -LastHasSRAM $LastHasSRAM -BaseCartDest $BaseCartDest -BaseSramDest $BaseSramDest -LogFile $LogFile -SessionStartTime $SessionStartTime.Value
	
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

Export-ModuleMember -Function Invoke-NESDump

