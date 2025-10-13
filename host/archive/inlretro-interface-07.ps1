# INL Retro Dumper Interface
# By Cosmic Katamari (@cosmickatamari)
# Last Updated: 09/17/2025

# PowerShell 7.x check
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7 or higher." -ForegroundColor Red
    exit 1
}

# -------- Focus helpers (no resize, fast) -----------------------------------
if (-not ("Win32FocusForce" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class Win32FocusForce {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    public const int SW_RESTORE = 9;
}
"@
}

function Get-CallerHwnd {
    $h = [System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle
    if ($h -and $h -ne [IntPtr]::Zero) { return $h }
    return [Win32FocusForce]::GetForegroundWindow()
}

function Restore-WindowForce {
    param([IntPtr]$Hwnd)
    if (-not $Hwnd -or $Hwnd -eq [IntPtr]::Zero) { return }

    # Only restore if minimized; don't change size otherwise
    if ([Win32FocusForce]::IsIconic($Hwnd)) {
        [Win32FocusForce]::ShowWindow($Hwnd, [Win32FocusForce]::SW_RESTORE) | Out-Null
    }

    # Bypass foreground lock so focus actually returns
    $fg = [Win32FocusForce]::GetForegroundWindow()
    $curThread = [Win32FocusForce]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
    $tgtThread = [Win32FocusForce]::GetWindowThreadProcessId($Hwnd, [IntPtr]::Zero)
    if ($curThread -ne 0 -and $tgtThread -ne 0 -and $curThread -ne $tgtThread) {
        [Win32FocusForce]::AttachThreadInput($curThread, $tgtThread, $true) | Out-Null
        [Win32FocusForce]::BringWindowToTop($Hwnd) | Out-Null
        [Win32FocusForce]::SetForegroundWindow($Hwnd) | Out-Null
        [Win32FocusForce]::AttachThreadInput($curThread, $tgtThread, $false) | Out-Null
    } else {
        [Win32FocusForce]::BringWindowToTop($Hwnd) | Out-Null
        [Win32FocusForce]::SetForegroundWindow($Hwnd) | Out-Null
    }
}
# ----------------------------------------------------------------------------

# Minimal helper to open URL in default browser and return focus
function Open-UrlInDefaultBrowser-AndReturn {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$DelayMs = 500
    )

    $prevHwnd = Get-CallerHwnd
    
    # Store current window state (for potential future use)
    # $wasMinimized = [Win32FocusForce]::IsIconic($prevHwnd)

    # Open URL in default browser
    Start-Process $Url

    # Wait for browser to load and steal focus
    Start-Sleep -Milliseconds $DelayMs
    
    # Force focus back with multiple attempts
    for ($i = 0; $i -lt 3; $i++) {
        Restore-WindowForce -Hwnd $prevHwnd
        Start-Sleep -Milliseconds 100
    }
}

# Initialize data directory and load external data files
$dataDir = Join-Path $PSScriptRoot "data"
$null = New-Item -ItemType Directory -Path $dataDir -Force

# Load external data files - required for script operation
try {
    $NESmapperMenu = Get-Content (Join-Path $dataDir "nes-mappers.json") -ErrorAction Stop | ConvertFrom-Json
    $consoleMap = Get-Content (Join-Path $dataDir "consoles.json") -ErrorAction Stop | ConvertFrom-Json
    $config = Get-Content (Join-Path $dataDir "config.json") -ErrorAction Stop | ConvertFrom-Json
    Write-Host "Configuration and data files loaded successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to load required data files from $dataDir"
    Write-Error "Please ensure the following files exist:"
    Write-Error "  - nes-mappers.json"
    Write-Error "  - consoles.json" 
    Write-Error "  - config.json"
    Write-Error "Error details: $($_.Exception.Message)"
    exit 1
}

# Create dumping folder locations efficiently
$directories = @(
    ".\ignore",
    ".\games\nes\sram",
    ".\games\snes\sram", 
    ".\games\n64\sram",
    ".\games\gameboy\sram",
    ".\games\genesis\sram",
	".\games\famicom\sram"
)

$directories | ForEach-Object { 
    $null = New-Item -ItemType Directory -Path $_ -Force 
}

function Read-Int([string]$prompt, [int]$minValue = [int]::MinValue, [int]$maxValue = [int]::MaxValue){
    while($true){
        $raw = Read-Host $prompt
        $result = 0
        if([int]::TryParse($raw, [ref]$result) -and $result -ge $minValue -and $result -le $maxValue){
            return $result
        }
        Write-Host "Please enter a valid number between $minValue and $maxValue." -ForegroundColor Yellow
    }
}

function Read-YesNo([string]$prompt){
    while($true){
        $v = (Read-Host "$prompt (y/n)").Trim().ToLower()
        if($v -in @('y','n')){ return $v }
        Write-Host "Please enter Y or N." -ForegroundColor Yellow
    }
}

function Read-KB-MultipleOf4([string]$prompt){
    while($true){
        $v = Read-Int $prompt
        if($v -ge 8 -and $v % 4 -eq 0){ return $v }
        Write-Host "Value must be increments of 4, starting with 8." -ForegroundColor Yellow
    }
}

function Wait-ForUserInput {
    Read-Host
}

function Show-Header {
    Clear-Host
	$Host.UI.RawUI.ForegroundColor = 'DarkCyan'

	Write-Host "  __  _   _  _       ____      _               ____                                 "
	Write-Host " |__|| \ | || |     |  _ \ ___| |_ ____ ___   |  _ \ _   _ ________  ____   ___ ___ "
	Write-Host "  || |  \| || |     | |_) / _ \ __|  __/ _ \  | | | | | | |  _   _ \|  _ \ / _ \ __|"
	Write-Host "  || | |\  || |___  |  _ <  __/ |_| | | (_) | | |_| | |_| | | | | | | |_) |  __/ |  "
	Write-Host " |__||_| \_||_____| |_| \_\___|\__|_|  \___/  |____/ \____|_| |_| |_|  __/ \___|_|  "
	Write-Host "  __        _             __                                        | |				"
	Write-Host " |__| ____ | |_ ___ ____ / _| ____  ___ ___ "
	Write-Host "  || |  _ \| __/ _ \  __| |_ / _  |/ __/ _ \"
	Write-Host "  || | | | | |_| __/ |  |  _| (_| | (_|  __/"
	Write-Host " |__||_| |_|\__\___|_|  |_|  \____|\___\___|"
	
	Write-Host "`n Created By:   	$($config.author)"
    Write-Host " Twitter/X:    	$($config.twitter)"
    Write-Host "`n Last Released: 9/28/2025"
    Write-Host " Version: 	$($config.version)"
    Write-Host "`n-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-"
	
	$Host.UI.RawUI.ForegroundColor = 'White'
}

function Select-Console {
    Write-Host "`n`nSelect A Console" -ForegroundColor Blue
    Write-Host
    Write-Host " 1 - Nintendo Entertainment System" -ForegroundColor White
	Write-Host " 2 - Nintendo Famicom (Family Computer)" -ForegroundColor White
    Write-Host " 3 - Super Nintendo Entertainment System" -ForegroundColor Yellow
    Write-Host " 4 - Nintendo 64" -ForegroundColor DarkGray
    Write-Host " 5 - Gameboy / Gameboy Advance" -ForegroundColor DarkGray
    Write-Host " 6 - Sega Genesis" -ForegroundColor DarkGray
    Write-Host
	
    $choice = Read-Int "Selection" -minValue 1 -maxValue 6
    return $consoleMap.($choice.ToString())
}

function Get-CartridgeName {
    while($true){
        $name = Read-Host "`nWhat is the name of your $sys game?"
        if([string]::IsNullOrWhiteSpace($name)){ continue }
        return $name.Trim()
    }
}

function Select-Mapper {
	$baseurl = "https://nescartdb.com/search/basic?keywords="
	$endurl  = "&kwtype=game"
	$encoded = [uri]::EscapeDataString($cartridge)
	$url     = $baseurl + $encoded + $endurl

    # Open default browser and return focus to the script
	Open-UrlInDefaultBrowser-AndReturn -Url $url -DelayMs 750

	Show-Header
	Write-Host "`nFor quicker access, the NES database has opened to the search results from the game title." -ForegroundColor Blue

    $columns = 5

    # Find the widest entry (number + name) so padding fits
    $maxLen = 0
    for ($i = 0; $i -lt $NESmapperMenu.Count; $i++) {
        $num = ($i+1).ToString("00")
        $entry = " {0}. {1}" -f $num, $NESmapperMenu[$i]
        if ($entry.Length -gt $maxLen) { $maxLen = $entry.Length }
    }
    $colWidth = $maxLen + 4  # add some extra spacing

    # Print mappers in table format
    for ($i = 0; $i -lt $NESmapperMenu.Count; $i++) {
        $num = ($i+1).ToString("00")
        $text = " {0}. {1}" -f $num, $NESmapperMenu[$i]
        Write-Host ($text.PadRight($colWidth)) -NoNewline

        if ( (($i+1) % $columns) -eq 0 ) {
            Write-Host
        }
    }
	
	Write-Host "`n"
    
    while ($true) {
		Write-Host "For AxROM cartridges, select the BNROM mapper." -ForegroundColor Cyan
		Write-Host "For MHROM cartridges, select the GxROM mapper." -ForegroundColor Cyan
		Write-Host "For MMC6 cartridges, select the MMC3 mapper." -ForegroundColor Cyan
        $ans = Read-Int "`nMapper Number"
        if ($ans -ge 1 -and $ans -le $NESmapperMenu.Count) {
            return $NESmapperMenu[$ans-1]
        }
        Write-Host ("Please choose between 1-{0}." -f $NESmapperMenu.Count) -ForegroundColor Yellow
    }
}

function Invoke-INLRetro {
    param(
        [string[]]$ArgsArray,
        [string]$CartDest,
        [string]$SramDest,
        [string]$HasSRAM
    )

    $exePath = Join-Path $PSScriptRoot 'inlretro.exe'
    
    # Check if executable exists
    if (-not (Test-Path $exePath)) {
        Write-Error "inlretro.exe not found at $exePath"
        return
    }

    $pretty = (
        $ArgsArray | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"','`"') + '"' } else { $_ }
        }
    ) -join ' '

    Write-Host "`nProgram and argument call used:" -ForegroundColor Blue
    Write-Host ".\inlretro.exe $pretty" -ForegroundColor Blue
    
    try {
        & $exePath @ArgsArray
        $exitCode = $LASTEXITCODE
    } catch {
        Write-Error "Failed to execute inlretro.exe: $($_.Exception.Message)"
        $exitCode = -1
    }
    
    Write-Host

    if ($exitCode -ne 0) {
        Write-Host "inlretro.exe exited with code $exitCode." -ForegroundColor Red
        Write-Host "`nThe cartridge could not be dumped." -ForegroundColor Red
    } else {
        Write-Host "`nYour cartridge dump is located at $CartDest." -ForegroundColor Green
        
        if ($HasSRAM -eq 'y') {
            Write-Host "Your save data is located at $SramDest." -ForegroundColor Green
            Write-Host "It will work with EverDrives and Emulators (such as Mesen)." -ForegroundColor Green
        }
        
        Write-Host "`nIt is safe to remove the cartridge." -ForegroundColor Cyan
        Write-Host "Pressing [ENTER] will restart the application, allowing for the next cartridge to be dumped." -ForegroundColor Cyan
    }
    
    Wait-ForUserInput
}

# -------------------------------- Main Loop ---------------------------------
while($true){
    Show-Header
    $sys = Select-Console
    $cartridge = Get-CartridgeName
	
    switch($sys){
		'Nintendo Entertainment System' {
			$nesmap = Select-Mapper
			$prg    = Read-KB-MultipleOf4 "`nWhat is the size (in KB) of the Program (PRG) ROM? (typically PRG0)"
			$hasChr	= Read-YesNo "`nDoes the cartridge have a Character (CHR) ROM? (typically CHR0)"
			$chr	= $null
			
			if ($hasChr -eq 'y') { 
				$chr = Read-KB-MultipleOf4 "What is the size (in KB) of the Character ROM?" 
				}

			$hasSRAM = Read-YesNo "`nDoes the cartridge contain a battery save (Working RAM)?"

			# Paths for storing files.
			$gamesRoot = Join-Path $PSScriptRoot 'games\nes'
			$cartdest  = Join-Path $gamesRoot "$cartridge.nes"
			$sramdest  = Join-Path (Join-Path $gamesRoot 'sram') "$cartridge.sav"

			# Arguments passed to the executable.
			$argsArray = @(
				'-s', (Join-Path $PSScriptRoot 'scripts\inlretro2.lua')
				'-c', 'NES'
				'-m', "$nesmap"
				'-x', "$prg"
				)

			if ($hasChr -eq 'y') { 
				$argsArray += @('-y', "$chr") 
				}
				
				$argsArray += @('-d', "$cartdest")
				
			if ($hasSRAM -eq 'y') { 
				$argsArray += @('-a', "$sramdest", '-w', '8') 
				}

			Invoke-INLRetro -ArgsArray $argsArray -CartDest $cartdest -SramDest $sramdest -HasSRAM $hasSRAM
			}
		
		'Nintendo Famicom (Family Computer)' {
			$nesmap = Select-Mapper
			$prg    = Read-KB-MultipleOf4 "`nWhat is the size (in KB) of the Program (PRG) ROM? (typically PRG0)"
			$hasChr	= Read-YesNo "`nDoes the cartridge have a Character (CHR) ROM? (typically CHR0)"
			$chr	= $null
			
			if ($hasChr -eq 'y') { 
				$chr = Read-KB-MultipleOf4 "What is the size (in KB) of the Character ROM?" 
				}

			$hasSRAM = Read-YesNo "`nDoes the cartridge contain a battery save (Working RAM)?"

			# Paths for storing files.
			$gamesRoot = Join-Path $PSScriptRoot 'games\famicom'
			$cartdest  = Join-Path $gamesRoot "$cartridge.nes"
			$sramdest  = Join-Path (Join-Path $gamesRoot 'sram') "$cartridge.sav"

			# Arguments passed to the executable.
			$argsArray = @(
				'-s', (Join-Path $PSScriptRoot 'scripts\inlretro2.lua')
				'-c', 'NES'
				'-m', "$nesmap"
				'-x', "$prg"
				)

			if ($hasChr -eq 'y') { 
				$argsArray += @('-y', "$chr") 
				}
				
				$argsArray += @('-d', "$cartdest")
				
			if ($hasSRAM -eq 'y') { 
				$argsArray += @('-a', "$sramdest", '-w', '8') 
				}

			Invoke-INLRetro -ArgsArray $argsArray -CartDest $cartdest -SramDest $sramdest -HasSRAM $hasSRAM
			}
		
		'Super Nintendo Entertainment System' {  # SNES
            $dest = ".\games\snes\$cartridge.sfc"
            $sram = ".\games\snes\sram\$cartridge.srm"
            $argsArray = @('-s', 'scripts/inlretro2.lua', '-c', 'SNES', '-d', $dest, '-a', $sram)
            Invoke-INLRetro -ArgsArray $argsArray -CartDest $dest -SramDest $sram -HasSRAM 'y'
        }
        'Nintendo 64' {  # N64 (placeholder)
            Write-Host "Add args as needed." -ForegroundColor Yellow
            Wait-ForUserInput
        }
        'Gameboy / Gameboy Advance' {  # Gameboy / GBA (placeholder)
            Write-Host "Add args as needed." -ForegroundColor Yellow
            Wait-ForUserInput
        }
        'Sega Genesis' {  # Sega Genesis (placeholder)
            Write-Host "Add args as needed." -ForegroundColor Yellow
            Wait-ForUserInput
        }
	}
}
