# INL Retro Dumper Interface
# By Cosmic Katamari (@cosmickatamari)
# Last Updated: 09/17/2025

# PowerShell 7.x check
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7 or higher." -ForegroundColor Red
    exit 1
}

# ----------------------------- Edge via DevTools (CDP) -----------------------------
# Session globals
if (-not $script:EdgeProcId)        { $script:EdgeProcId        = $null }
if (-not $script:EdgeCDPPort)       { $script:EdgeCDPPort       = 9222 }
if (-not $script:EdgeWS)            { $script:EdgeWS            = $null }
if (-not $script:EdgePageEnabled)   { $script:EdgePageEnabled   = $false }

function Start-EdgeIfNeeded {
    param([Parameter(Mandatory)] [string]$InitialUrl)

    $alive = $false
    if ($script:EdgeProcId) {
        try { Get-Process -Id $script:EdgeProcId -ErrorAction Stop | Out-Null; $alive = $true } catch {}
    }
    if ($alive) { return }

    # First open: pass URL (quoted) so Edge lands directly on the page
    $args = @(
        "--remote-debugging-port=$($script:EdgeCDPPort)",
        "--new-window",
        "`"$InitialUrl`""
    )
    $p = Start-Process -FilePath "msedge.exe" -ArgumentList $args -PassThru
    $script:EdgeProcId      = $p.Id
    $script:EdgeWS          = $null
    $script:EdgePageEnabled = $false

    # Quick probe for DevTools (kept tight for speed)
    $deadline = (Get-Date).AddSeconds(1.2)
    do {
        try {
            $null = Invoke-RestMethod -Uri "http://127.0.0.1:$($script:EdgeCDPPort)/json/version" -TimeoutSec 0.3
            break
        } catch { Start-Sleep -Milliseconds 100 }
    } while ((Get-Date) -lt $deadline)
}

function Get-EdgeTabWebSocket {
    try {
        $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:$($script:EdgeCDPPort)/json" -TimeoutSec 0.5
    } catch {
        $script:EdgeWS = $null; return $null
    }

    $candidate = $tabs | Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl } |
        Sort-Object { if ($_.url -match 'nescartdb\.com') { 0 } else { 1 } }, title |
        Select-Object -First 1

    $script:EdgeWS = $candidate?.webSocketDebuggerUrl
    return $script:EdgeWS
}

function Ensure-EdgeWs {
    param([string]$FallbackUrl)
    if ($script:EdgeWS) { return $script:EdgeWS }

    $ws = Get-EdgeTabWebSocket
    if ($ws) { return $ws }

    # No page yet — create one directly with your URL so we have a target
    if ($FallbackUrl) {
        $q = [uri]::EscapeDataString($FallbackUrl)
        try {
            $new = Invoke-RestMethod -Uri "http://127.0.0.1:$($script:EdgeCDPPort)/json/new?url=$q" -TimeoutSec 0.6
            $script:EdgeWS = $new?.webSocketDebuggerUrl
        } catch { $script:EdgeWS = $null }
    }
    return $script:EdgeWS
}

function Invoke-Cdp {
    param(
        [Parameter(Mandatory)][string]$WsUrl,
        [Parameter(Mandatory)][hashtable]$Message
    )
    Add-Type -AssemblyName System.Net.WebSockets

    $json = ($Message | ConvertTo-Json -Depth 6)
    $uri  = [Uri]$WsUrl
    $ws   = [System.Net.WebSockets.ClientWebSocket]::new()
    $cts  = [System.Threading.CancellationTokenSource]::new()
    $cts.CancelAfter(450)  # ~0.45s per call

    $ws.ConnectAsync($uri, $cts.Token).Wait()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg   = [ArraySegment[byte]]::new($bytes, 0, $bytes.Length)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
    try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $cts.Token).Wait() } catch {}
    $ws.Dispose() | Out-Null
}

function Navigate-Edge {
    param([Parameter(Mandatory)][string]$Url)

    # First run: ensure Edge is up and already pointed at the site
    Start-EdgeIfNeeded -InitialUrl $Url

    # Reuse the same tab thereafter
    $ws = Ensure-EdgeWs -FallbackUrl $Url
    if (-not $ws) { return }

    # Enable Page domain only once per session/tab to save ~400ms next calls
    if (-not $script:EdgePageEnabled) {
        Invoke-Cdp -WsUrl $ws -Message @{ id=1; method="Page.enable"; params=@{} }
        $script:EdgePageEnabled = $true
    }

    # Navigate (single quick CDP call)
    Invoke-Cdp -WsUrl $ws -Message @{ id=2; method="Page.navigate"; params=@{ url=$Url; transitionType="typed" } }
}

# ----------------------------- Focus helpers (no resize) -----------------------------
# New type name to avoid older cached class without IsIconic
if (-not ("Win32FocusEx" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class Win32FocusEx {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    public const int SW_RESTORE = 9;
}
"@
}

function Get-CurrentHwnd { [Win32FocusEx]::GetForegroundWindow() }

function Restore-Window {
    param([IntPtr]$Hwnd)
    if (-not $Hwnd -or $Hwnd -eq [IntPtr]::Zero) { return }
    # Only restore if minimized; otherwise don’t touch size/position
    if ([Win32FocusEx]::IsIconic($Hwnd)) {
        [Win32FocusEx]::ShowWindow($Hwnd, [Win32FocusEx]::SW_RESTORE) | Out-Null
    }
    [Win32FocusEx]::SetForegroundWindow($Hwnd) | Out-Null
    Start-Sleep -Milliseconds 60
}

# Checking for and creating dumping folder locations.
$null = New-Item -ItemType Directory -Path ".\ignore" -Force
$null = New-Item -ItemType Directory -Path ".\games\nes\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\snes\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\n64\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\gameboy\sram" -Force
$null = New-Item -ItemType Directory -Path ".\games\genesis\sram" -Force

$NESmapperMenu = @(
    'Action53','Action53_TSOP','BNROM','CDREAM','CNINJA','CNROM','DualPort','EasyNSF','FME7','GTROM',
    'Mapper30','Mapper30v2','MMC1','MMC2','MMC3','MMC4','MMC5','NROM','UNROM','UNROM_TSOP'
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
        if ([int]::TryParse($raw, [ref]([int]$null))) { return [int]$raw }
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

function Pause-Continue { Read-Host }

function Show-Header {
    Clear-Host
    Write-Host "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-"
    Write-Host "INL Retro Dumper Interface"
    Write-Host "Created By:   	Cosmic Katamari"
    Write-Host "X/Twitter:    	@cosmickatamari"
    Write-Host "`nLast Updated: 	9/17/2025"
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
        if ($consoleMap.ContainsKey($choice)) { return $consoleMap[$choice] }
        Write-Host "Please choose a between 1-5." -ForegroundColor Yellow
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
    # Build the NESCartDB search URL (spaces/symbols safe)
    $baseurl = "https://nescartdb.com/search/basic?keywords="
    $endurl  = "&kwtype=game"
    $encoded = [uri]::EscapeDataString($cartridge)
    $url     = $baseurl + $encoded + $endurl

    # Navigate Edge (single tab, no new windows/tabs)
	$prevHwnd = Get-CurrentHwnd
	Navigate-Edge -Url $url
	Restore-Window -Hwnd $prevHwnd

    Show-Header
    Write-Host "`nUsing the (Game Title) search field, a web browser is open to the results for quicker access." -ForegroundColor Blue
    Write-Host "`nWhich Mapper (hardware) does the cartridge use?"

    $columns = 5

    # Layout sizing
    $maxLen = 0
    for ($i = 0; $i -lt $NESmapperMenu.Count; $i++) {
        $num = ($i+1).ToString("00")
        $entry = " {0}. {1}" -f $num, $NESmapperMenu[$i]
        if ($entry.Length -gt $maxLen) { $maxLen = $entry.Length }
    }
    $colWidth = $maxLen + 4

    # Print in columns
    for ($i = 0; $i -lt $NESmapperMenu.Count; $i++) {
        $num = ($i+1).ToString("00")
        $text = " {0}. {1}" -f $num, $NESmapperMenu[$i]
        Write-Host ($text.PadRight($colWidth)) -NoNewline
        if ( (($i+1) % $columns) -eq 0 ) { Write-Host }
    }
    Write-Host

    while ($true) {
        $ans = Read-Int "`nMapper Number"
        if ($ans -ge 1 -and $ans -le $NESmapperMenu.Count) { return $NESmapperMenu[$ans-1] }
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
            Write-Host "Both should work with EverDrives and Emulators (such as Mesen, etc.)" -ForegroundColor Green
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
            $hasChr = Read-YesNo "`nDoes the cartridge have a Character (CHR) ROM? (typically CHR0)"
            $chr    = $null
            if ($hasChr -eq 'y') { $chr = Read-KB-MultipleOf4 "What is the size (in KB) of the Character ROM?" }
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
            if ($hasChr -eq 'y')  { $argsArray += @('-y', "$chr") }
            if ($hasSRAM -eq 'y') { $argsArray += @('-a', "$sramdest", '-w', '8') }

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