# INLinterface.Console.Famicom.psm1
# Nintendo Famicom (Family Computer) console-specific dumping workflow.
# This module handles the complete Famicom cartridge dumping process.

<#
	Handles Nintendo Famicom (Family Computer) cartridge dumping workflow.
	Guides the user through the Famicom dumping process, executes the dump, and handles post-dump operations.
	Returns true on success, false on failure, or exits the application on critical errors.
#>
function Invoke-FamicomDump {
	param(
		[Parameter(Mandatory)]
		[string]$CartridgeName,
		
		[Alias('PSScriptRoot')]
		[string]$HostScriptRoot,
		
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
	
	$dumpSuccess = Invoke-NESBasedCartridgeDump -ConsoleFolderName 'famicom' -CartridgeName $CartridgeName -PSScriptRoot $HostScriptRoot -LogDir $LogDir -NESmapperMenu $NESmapperMenu -BrowserNesDelayMs 750 -TimesDumped $TimesDumped -LastArgsArray $LastArgsArray -LastCartDest $LastCartDest -LastSramDest $LastSramDest -LastHasSRAM $LastHasSRAM -BaseCartDest $BaseCartDest -BaseSramDest $BaseSramDest -LogFile $LogFile -SessionStartTime $SessionStartTime.Value
	
	if ($dumpSuccess) {
		ReDump -LastArgsArray $LastArgsArray -BaseCartDest $BaseCartDest -BaseSramDest $BaseSramDest -LastHasSRAM $LastHasSRAM -TimesDumped $TimesDumped -BrowserPromptShown $BrowserPromptShown -PSScriptRoot $HostScriptRoot -LogFile $LogFile -SessionStartTime $SessionStartTime.Value -IgnoreDir $IgnoreDir
	} else {
		Write-Host "The dump failed. Please check the error messages above." -ForegroundColor Red
		Write-Host "Exiting due to failure." -ForegroundColor Red
		Show-LogFileLocation -TimesDumped $TimesDumped.Value -LogFile $LogFile
		Remove-IgnoreFolder -IgnoreDir $IgnoreDir
		exit 1
	}
}

Export-ModuleMember -Function Invoke-FamicomDump

