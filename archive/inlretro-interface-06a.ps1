# INL Retro Dumper Interface
# By Cosmic Katamari (@cosmickatamari)
# Last Updated: 09/15/2025

# PowerShell 7.5.x check
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7 or higher." -ForegroundColor Red
    exit 1
}

if (-not $script:EdgeProcId) { $script:EdgeProcId = $null }
if (-not $script:EdgeCDPPort) { $script:EdgeCDPPort = 9222 }  # change if needed
if (-not $script:EdgeWS) { $script:EdgeWS = $null }           # cached websocket URL to the tab
if (-not $script:EdgeTargetId) { $script:EdgeTargetId = $null }

function Start-EdgeIfNeeded {
    param([string]$InitialUrl)

    # Is our Edge still alive?
    $alive = $false
    if ($script:EdgeProcId) {
        try { Get-Process -Id $script:EdgeProcId -ErrorAction Stop | Out-Null; $alive = $true } catch {}
    }

    if (-not $alive) {
        # Launch Edge once with a DevTools port (uses your normal profile; no new profile dirs)
        $args = @("--remote-debugging-port=$($script:EdgeCDPPort)", "--new-window", $InitialUrl)
        $p = Start-Process -FilePath "msedge.exe" -ArgumentList $args -PassThru
        $script:EdgeProcId = $p.Id

        # Wait for DevTools HTTP to come up
        $deadline = (Get-Date).AddSeconds(8)
        do {
            try {
                $null = Invoke-RestMethod -Uri "http://127.0.0.1:$($script:EdgeCDPPort)/json/version" -TimeoutSec 1
                break
            } catch { Start-Sleep -Milliseconds 150 }
        } while ((Get-Date) -lt $deadline)

        # Give the initial tab a moment to appear
        Start-Sleep -Milliseconds 400
        # Cache the tab's websocket once
        Get-EdgeTabWebSocket | Out-Null
    }
}

function Get-EdgeTabWebSocket {
    # Pick the most relevant tab (NESCartDB if present; otherwise first "page" type)
    try {
        $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$($script:EdgeCDPPort)/json" -TimeoutSec 2
    } catch {
        $script:EdgeWS = $null; return $null
    }

    $candidate = $tabs | Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl } |
        Sort-Object { if ($_.url -match 'nescartdb\.com') { 0 } else { 1 } }, title |
        Select-Object -First 1

    if ($candidate) {
        $script:EdgeTargetId = $candidate.id
        $script:EdgeWS = $candidate.webSocketDebuggerUrl
        return $script:EdgeWS
    }

    $script:EdgeWS = $null
    return $null
}

function Invoke-Cdp {
    param(
        [string]$WsUrl,
        [hashtable]$Message
    )
    # Minimal CDP client over ClientWebSocket
    Add-Type -AssemblyName System.Net.Http
    Add-Type -AssemblyName System.Net.WebSockets

    $json = ($Message | ConvertTo-Json -Depth 6)
    $uri = [Uri]$WsUrl
    $ws  = [System.Net.WebSockets.ClientWebSocket]::new()
    $cts = [System.Threading.CancellationTokenSource]::new()
    $cts.CancelAfter(3000)

    $ws.ConnectAsync($uri, $cts.Token).Wait()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg   = [ArraySegment[byte]]::new($bytes, 0, $bytes.Length)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()

    # Read one small response (best effort)
    $buf = New-Object byte[] 8192
    $segIn = [ArraySegment[byte]]::new($buf, 0, $buf.Length)
    try { $ws.ReceiveAsync($segIn, $cts.Token).Wait() } catch {}
    $ws.Dispose() | Out-Null
}

function Navigate-Edge {
    param([string]$Url)

    # Ensure Edge + DevTools are running
    Start-EdgeIfNeeded -InitialUrl $Url

    # Ensure we have a websocket to a tab
    if (-not $script:EdgeWS) { Get-EdgeTabWebSocket | Out-Null }
    if (-not $script:EdgeWS) { return }  # nothing we can do

    # Enable Page domain and navigate the existing tab (no new tabs/windows)
    $id = 1
    Invoke-Cdp -WsUrl $script:EdgeWS -Message @{ id=$id; method="Page.enable"; params=@{} }
    $id++
    Invoke-Cdp -WsUrl $script:EdgeWS -Message @{ id=$id; method="Page.navigate"; params=@{ url=$Url; transitionType="typed" } }
}

if (-not ("Win32Focus" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class Win32Focus {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public const int SW_RESTORE = 9;
}
"@
}

function Get-CurrentHwnd {
    return [Win32Focus]::GetForegroundWindow()
}

function Restore-Window {
    param([IntPtr]$Hwnd)
    if ($Hwnd -and $Hwnd -ne [IntPtr]::Zero) {
        [Win32Focus]::ShowWindow($Hwnd, [Win32Focus]::SW_RESTORE) | Out-Null
        [Win32Focus]::SetForegroundWindow($Hwnd) | Out-Null
        Start-Sleep -Milliseconds 80
    }
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
        $v = Read-Host $prompt
        if([int]::TryParse($v, [ref]([int]$null))){
            return [int]$v
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
	Write-Host "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-"
    Write-Host "INL Retro Dumper Interface"
    Write-Host "Created By:   	Cosmic Katamari"
    Write-Host "X/Twitter:    	@cosmickatamari"
    Write-Host "`nLast Updated: 	9/14/2025"
    Write-Host "Release: 	0.05"
    Write-Host "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-"
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
	$url = $baseurl + $cartridge + $endurl
	$prevHwnd = Get-CurrentHwnd

	
	Start-Process -FilePath "msedge.exe" -ArgumentList @("--new-window", "`"$url`"") -PassThru
	Restore-Window -Hwnd $prevHwnd


	Show-Header
	Write-Host "`nUsing the (Game Title) search field, a web browser is open to the results for quicker access." -ForegroundColor Blue
    Write-Host "`nWhich Mapper (hardware) does the cartridge use?"

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
    
	Write-Host  # final newline for incomplete rows

    while ($true) {
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
				'-d', "$cartdest"
			)

			if ($hasChr -eq 'y') { 
				$argsArray += @('-y', "$chr") 
				}
				
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