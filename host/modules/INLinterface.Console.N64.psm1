# INLinterface.Console.N64.psm1
# Nintendo 64 cartridge dumping workflow (ROM-only; size auto-detected in Lua when -k omitted).

<#
	Runs inlretro.exe for Nintendo 64: big-endian .z64 output under games\n64.
	ROM size is auto-detected by host/scripts/n64/basic.lua (data/n64-gameid.tsv + mirror) when -k is not passed.
	Save data (EEPROM/SRAM/Flash) is not dumped by current firmware.
#>D:
function Invoke-N64Dump {
	param(
		[Parameter(Mandatory)]
		[string]$CartridgeName,
		
		[Alias('PSScriptRoot')]
		[string]$HostScriptRoot,
		
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
	
	if ($null -eq $SessionStartTime.Value) {
		$SessionStartTime.Value = Get-Date
	}
	
	$gamesRoot = Join-Path $HostScriptRoot 'games\n64'
	$cartDest = Join-Path $gamesRoot "$CartridgeName.z64"
	$luaScript = Join-Path $HostScriptRoot 'scripts\inlretro2.lua'
	$sramDest = ''
	$hasSRAM = $false
	
	[void](New-Item -ItemType Directory -Path $gamesRoot -Force)
	[void](New-Item -ItemType Directory -Path $LogDir -Force)
	
	$argsArray = @(
		'-s', $luaScript
		'-c', 'n64'
		'-d', $cartDest
	)
	
	$dumpSuccess = Invoke-INLRetro -ArgsArray $argsArray -CartDest $cartDest -SramDest $sramDest -HasSRAM $hasSRAM `
		-CartridgeTitle "" -ParametersUsedCaption 'Parameters used (game ROM only):' -DeferParametersBannerToLua $true -PSScriptRoot $HostScriptRoot -TimesDumped $TimesDumped -LastArgsArray $LastArgsArray `
		-LastCartDest $LastCartDest -LastSramDest $LastSramDest -LastHasSRAM $LastHasSRAM `
		-BaseCartDest $BaseCartDest -BaseSramDest $BaseSramDest -LogFile $LogFile -SessionStartTime $SessionStartTime.Value
	
	if ($dumpSuccess) {
		ReDump -LastArgsArray $LastArgsArray -BaseCartDest $BaseCartDest -BaseSramDest $BaseSramDest -LastHasSRAM $LastHasSRAM `
			-TimesDumped $TimesDumped -BrowserPromptShown $BrowserPromptShown -PSScriptRoot $HostScriptRoot `
			-LogFile $LogFile -SessionStartTime $SessionStartTime.Value -IgnoreDir $IgnoreDir
	} else {
		Write-Host "The dump failed. Please check the error messages above." -ForegroundColor Red
		Write-Host "Exiting due to failure." -ForegroundColor Red
		Show-LogFileLocation -TimesDumped $TimesDumped.Value -LogFile $LogFile
		Remove-IgnoreFolder -IgnoreDir $IgnoreDir
		exit 1
	}
}

Export-ModuleMember -Function Invoke-N64Dump
