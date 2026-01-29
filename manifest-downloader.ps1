param(
    [string]$ApiKey,
    [string]$AppId
)

# Set console encoding to UTF8
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

    $barFilled = "#" * $filled
    $barEmpty = "-" * $empty

    Write-Host ("`r  {0} [{1}" -f $Label, $barFilled) -NoNewline
    Write-Host $barEmpty -NoNewline -ForegroundColor DarkGray
    Write-Host ("] {0}% ({1}/{2})    " -f $percent, $Current, $Total) -NoNewline
}

function Write-Status {
    param(
        [string]$Message,
        [ConsoleColor]$Color = "White"
    )
    Write-Host "  [*] $Message" -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [+] $Message" -ForegroundColor Green
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "  [-] $Message" -ForegroundColor Red
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
}

function Get-SteamPath {
    $registryPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )

    foreach ($path in $registryPaths) {
        try {
            $steamPath = (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue).InstallPath
            if ($steamPath -and (Test-Path $steamPath)) {
                return $steamPath
            }
        } catch {}
    }
    return $null
}

function Get-DepotIdsFromLua {
    param([string]$LuaPath)

    $depots = @()
    $content = Get-Content -Path $LuaPath -ErrorAction Stop

    foreach ($line in $content) {
        if ($line -match 'addappid\s*\(\s*(\d+)\s*,\s*\d+\s*,\s*"[a-fA-F0-9]+"') {
            $depots += $matches[1]
        }
    }

    return $depots | Select-Object -Unique
}

function Get-AppInfo {
    param([string]$AppId)

    try {
        return Invoke-RestMethod "https://api.steamcmd.net/v1/info/$AppId" -TimeoutSec 30
    } catch {
        return $null
    }
}

function Get-ManifestIdForDepot {
    param(
        [object]$AppInfo,
        [string]$AppId,
        [string]$DepotId
    )

    try {
        return $AppInfo.data.$AppId.depots.$DepotId.manifests.public.gid
    } catch {
        return $null
    }
}

function Download-Manifest {
    param(
        [string]$ApiKey,
        [string]$DepotId,
        [string]$ManifestId,
        [string]$OutputPath
    )

    $url = "https://api.manifesthub1.filegear-sg.me/manifest?apikey=$ApiKey&depotid=$DepotId&manifestid=$ManifestId"
    $outputFile = Join-Path $OutputPath "${DepotId}_${ManifestId}.manifest"

    try {
        Invoke-WebRequest $url -OutFile $outputFile -TimeoutSec 120
        if ((Get-Item $outputFile).Length -gt 0) {
            return $true
        }
    } catch {}
    return $false
}

# ========================= MAIN =========================

if (-not $ApiKey) { $ApiKey = Read-Host "Enter ManifestHub API Key" }
if (-not $AppId)  { $AppId  = Read-Host "Enter Steam AppID" }

$steamPath = Get-SteamPath
if (-not $steamPath) { Write-ErrorMsg "Steam not found"; exit }

$luaPath = Join-Path $steamPath "config\stplug-in\$AppId.lua"
if (-not (Test-Path $luaPath)) { Write-ErrorMsg "Lua file not found"; exit }

$depots = Get-DepotIdsFromLua $luaPath
$appInfo = Get-AppInfo $AppId

$cachePath = Join-Path $steamPath "depotcache"
if (-not (Test-Path $cachePath)) {
    New-Item -ItemType Directory -Path $cachePath | Out-Null
}

foreach ($depot in $depots) {
    $manifest = Get-ManifestIdForDepot $appInfo $AppId $depot
    if ($manifest) {
        Write-Status "Downloading Depot $depot"
        if (Download-Manifest $ApiKey $depot $manifest $cachePath) {
            Write-Success "Depot $depot done"
        } else {
            Write-ErrorMsg "Depot $depot failed"
        }
    }
}

Write-Host "`nDone."
