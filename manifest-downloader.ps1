param(
    [string]$ApiKey,
    [string]$AppId
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Steam Manifest Downloader (For Steamtools)"

function Write-ProgressBar {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Label,
        [int]$Width = 40,
        [ConsoleColor]$Color = "Green"
    )

    $percent = if ($Total -gt 0) { [math]::Round(($Current / $Total) * 100) } else { 0 }
    $filled = [math]::Floor(($Current / [math]::Max($Total, 1)) * $Width)
    $empty = $Width - $filled

    Write-Host ("`r  {0} [{1}{2}] {3}% ({4}/{5})    " -f `
        $Label,
        ("#" * $filled),
        ("-" * $empty),
        $percent,
        $Current,
        $Total
    ) -NoNewline
}

function Write-Status { param([string]$m) Write-Host "  [*] $m" }
function Write-Success { param([string]$m) Write-Host "  [+] $m" -ForegroundColor Green }
function Write-ErrorMsg { param([string]$m) Write-Host "  [-] $m" -ForegroundColor Red }
function Write-WarningMsg { param([string]$m) Write-Host "  [!] $m" -ForegroundColor Yellow }

function Get-SteamPath {
    $paths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )
    foreach ($p in $paths) {
        try {
            $sp = (Get-ItemProperty $p -ErrorAction SilentlyContinue).InstallPath
            if ($sp -and (Test-Path $sp)) { return $sp }
        } catch {}
    }
    return $null
}

function Get-DepotIdsFromLua {
    param([string]$LuaPath)
    $ids = @()
    foreach ($l in Get-Content $LuaPath) {
        if ($l -match 'addappid\s*\(\s*(\d+)\s*,\s*\d+\s*,\s*"[a-fA-F0-9]+"') {
            $ids += $matches[1]
        }
    }
    return $ids | Select-Object -Unique
}

function Get-AppInfo {
    param([string]$AppId)
    try {
        Invoke-RestMethod "https://api.steamcmd.net/v1/info/$AppId" -TimeoutSec 30
    } catch { $null }
}

function Get-ManifestIdForDepot {
    param($AppInfo, $AppId, $DepotId)
    try {
        $AppInfo.data.$AppId.depots.$DepotId.manifests.public.gid
    } catch { $null }
}

function Download-Manifest {
    param(
        [string]$ApiKey,
        [string]$DepotId,
        [string]$ManifestId,
        [string]$OutputPath,
        [int]$MaxRetries = 5
    )

    $url = "https://api.manifesthub1.filegear-sg.me/manifest?apikey=$ApiKey&depotid=$DepotId&manifestid=$ManifestId"
    $out = Join-Path $OutputPath "${DepotId}_${ManifestId}.manifest"

    for ($i=1; $i -le $MaxRetries; $i++) {
        try {
            if (Test-Path $out) { Remove-Item $out -Force }
            Invoke-WebRequest $url -OutFile $out -TimeoutSec 120
            if ((Get-Item $out).Length -gt 0) { return $true }
        } catch {}
        Start-Sleep 3
    }
    return $false
}

if (-not $ApiKey) { $ApiKey = Read-Host "Enter ManifestHub API Key" }
if (-not $AppId)  { $AppId  = Read-Host "Enter Steam AppID" }

$steam = Get-SteamPath
if (-not $steam) { Write-ErrorMsg "Steam not found"; exit }

$lua = Join-Path $steam "config\stplug-in\$AppId.lua"
if (-not (Test-Path $lua)) { Write-ErrorMsg "Lua file not found"; exit }

$depots = Get-DepotIdsFromLua $lua
$appInfo = Get-AppInfo $AppId

$cache = Join-Path $steam "depotcache"
if (-not (Test-Path $cache)) { New-Item -ItemType Directory $cache | Out-Null }

foreach ($d in $depots) {
    $m = Get-ManifestIdForDepot $appInfo $AppId $d
    if ($m) {
        Write-Status "Downloading depot $d"
        if (Download-Manifest $ApiKey $d $m $cache) {
            Write-Success "Depot $d done"
        } else {
            Write-ErrorMsg "Depot $d failed"
        }
    }
}

Write-Host "`nDone."
