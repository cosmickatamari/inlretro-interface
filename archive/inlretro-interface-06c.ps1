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

# Minimal helper to open Edge and come back
function Open-UrlInEdge-AndReturn {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$DelayMs = 350  # tweak 250–500 if needed for your box
    )

    $prevHwnd = Get-CallerHwnd

    # Quote the URL so spaces/apostrophes don't split into multiple args
    Start-Process -FilePath "msedge.exe" -ArgumentList @("`"$Url`"")

    # Tiny delay so Edge can steal focus, then we take it back
    Start-Sleep -Milliseconds $DelayMs
    Restore-WindowForce -Hwnd $prevHwnd
}

# Checking for and creating dumping folder locations.
$null = New-Item -ItemType Directory -Path ".\ignore" -Force
$null = New-Item -ItemType Directory -Path ".\games\nes\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\snes\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\n64\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\gameboy\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\genesis\sram" -Force

$NESmapperMenu = @(
    'Action53',
    'Action53_TSOP',
    'BNROM',
    'CDREAM',
    'CNINJA',
    'CNROM',
    'DualPort',
    'EasyNSF',
    'FME7',
	'GTROM',
	'GxROM',
    'Mapper30',
    'Mapper30v2',
    'MMC1',
	'MMC2',
    'MMC3',
    'MMC4',
    'MMC5',
    'NROM',
    'UNROM', 
	'UNROM_TSOP'
)

$consoleMap = @{
	1 = "Nintendo Entertainment System"
	2 = "Super Nintendo Entertainment System"
	3 = "Nintendo 64"
	4 = "Gameboy"
	5 = "Sega Genesis"
}

function Read-Int([string]$prompt){
    while($true){
        $raw = Read-Host $prompt
        if([int]::TryParse($raw, [ref]([int]$null))){
            return [int]$raw
        }
        Write-Host "Please enter a valid selection." -ForegroundColor Yellow
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

function Pause-Continue {
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
	
	Write-Host "`n Created By:   	Cosmic Katamari"
    Write-Host " Twitter/X:    	@cosmickatamari"
    Write-Host "`n Last Released: 9/17/2025"
    Write-Host " Version: 	0.06c"
    Write-Host "`n-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-+-+-+-+-+--+-+-+-+-+-+-+-+-+-+-"
	
	$Host.UI.RawUI.ForegroundColor = 'White'
}

function Select-Console {
    Write-Host "`n`nSelect A Console" -ForegroundColor Blue
    Write-Host
    Write-Host " 1 - Nintendo Entertainment System" -ForegroundColor Yellow
    Write-Host " 2 - Super Nintendo Entertainment System" -ForegroundColor Yellow
    Write-Host " 3 - Nintendo 64" -ForegroundColor DarkGray
    Write-Host " 4 - Gameboy / Gameboy Advance" -ForegroundColor DarkGray
    Write-Host " 5 - Sega Genesis" -ForegroundColor DarkGray
    Write-Host
	
    while ($true) {
        $choice = Read-Int "Selection"
        if ($consoleMap.ContainsKey($choice)) {
            return $consoleMap[$choice]
        }
        else {
            Write-Host "Please choose a between 1-5." -ForegroundColor Yellow
        }
    }
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

    # Open Edge and return focus to the script (not always working)
	Open-UrlInEdge-AndReturn -Url $url -DelayMs 750

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

function Run-INL {
    param([string[]]$ArgsArray)

    $pretty = (
        $ArgsArray | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"','`"') + '"' } else { $_ }
        }
    ) -join ' '

    Write-Host "`nProgram and argument call used:" -ForegroundColor Blue
	Write-Host ".\inlretro.exe $pretty" -ForegroundColor Blue
	& (Join-Path $PSScriptRoot 'inlretro.exe') @ArgsArray
	Write-Host

    if ($LASTEXITCODE -ne 0) {
        Write-Host "inlretro.exe exited with code $LASTEXITCODE." -ForegroundColor Red
		Write-Host "`nThe cartridge could not be dumped." -ForegroundColor Red
		} else {
		
		Write-Host "`nYour cartridge dump is located at $cartdest." -ForegroundColor Green
		
		if ($hasSRAM -eq 'y') {
			Write-Host "Your save data is located at $sramdest." -ForegroundColor Green
			Write-Host "It will work with EverDrives and Emulators (such as Mesen)." -ForegroundColor Green
		}
		
		Write-Host "`nIt is safe to remove the cartridge." -ForegroundColor Cyan
		Write-Host "Pressing [ENTER] will restart the application, allowing for the next cartridge to be dumped." -ForegroundColor Cyan
	}
	
	Pause-Continue
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

			Run-INL $argsArray
			}
		
        2 {  # SNES
            $dest = ".\games\snes\$cartridge.sfc"
            $sram = ".\games\snes\sram\$cartridge.srm"
            Run-INL "-s scripts/inlretro2.lua -c SNES -d `"$dest`" -a `"$sram`""
            Pause-Continue
        }
        3 {  # N64 (placeholder)
            Write-Host "Add args as needed." -ForegroundColor Yellow
            Pause-Continue
        }
        4 {  # Gameboy / GBA (placeholder)
            Write-Host "Add args as needed." -ForegroundColor Yellow
            Pause-Continue
        }
        5 {  # Sega Genesis (placeholder)
            Write-Host "Add args as needed." -ForegroundColor Yellow
            Pause-Continue
        }
	}
}
