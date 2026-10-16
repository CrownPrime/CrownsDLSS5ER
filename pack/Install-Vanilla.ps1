<#
  Elden Ring DLSS 5 - installer for normal (unmodded) ELDEN RING, launched through a bundled me3.

  Installs:
    <ELDEN RING>\CrownsDLSS5\EldenRingDLSS\   ReShade 6.8 (add-on build) + patched EldenRingDLSS add-on + DLSS DLLs
    <ELDEN RING>\CrownsDLSS5\me3\             me3 (mod loader) that starts the game without Easy Anti-Cheat
    <ELDEN RING>\CrownsDLSS5\eldenring-dlss5.me3, Start_EldenRing_DLSS5.bat
    <Game>\OptiScaler.dll, OptiScaler.ini, OptiScaler\, nvngx_dlss.dll, nvngx_dlssnr.dll (CrownsDLSS5_users.txt
    records which installs use them)

  Existing EldenRingDLSS.ini / OptiScaler.ini are kept unless -ResetSettings is given.
#>
param(
  [Parameter(Mandatory = $true)][string]$GameDir,
  [string]$ModsFile = '',
  [switch]$SkipSteamInit,  # me3 --skip-steam-init: start the game without initialising Steam
  [switch]$ResetSettings
)
$ErrorActionPreference = 'Stop'
$pack = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = Join-Path $pack 'files'

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path (Join-Path $GameDir 'eldenring.exe'))) { Fail "eldenring.exe not found in '$GameDir'." }
$GameDir = (Resolve-Path $GameDir).Path
$gameExe = Join-Path $GameDir 'eldenring.exe'
if (Get-Process eldenring -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $gameExe }) { Fail 'Close ELDEN RING first.' }
if (Test-Path (Join-Path $GameDir 'dxgi.dll')) {
  Write-Host "WARNING: '$GameDir\dxgi.dll' exists. Another proxy DLL there can conflict with this setup." -ForegroundColor Yellow
}

$root = Join-Path (Split-Path -Parent $GameDir) 'CrownsDLSS5'
$addonDir = Join-Path $root 'EldenRingDLSS'
$installed = New-Object System.Collections.Generic.List[string]

function Put([string]$src, [string]$dst, [bool]$isSettings = $false) {
  if ($isSettings -and (Test-Path $dst) -and -not $ResetSettings) {
    Write-Host "  kept your settings: $dst"
  } else {
    New-Item -ItemType Directory -Force (Split-Path -Parent $dst) | Out-Null
    Copy-Item $src $dst -Force
  }
  $installed.Add($dst)
}

function Put-Tree([string]$from, [string]$to, [string[]]$settings) {
  Get-ChildItem $from -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($from.Length + 1)
    Put $_.FullName (Join-Path $to $rel) ($settings -contains $rel)
  }
}

# The DLSS 5 model is supplied by the user (NVIDIA's file is not redistributable).
if (-not (Test-Path (Join-Path $files 'Game\nvngx_dlssnr.dll')) -and -not (Test-Path (Join-Path $GameDir 'nvngx_dlssnr.dll'))) {
  Write-Host 'WARNING: nvngx_dlssnr.dll (the DLSS 5 model) was not found in pack\files\Game or the game folder.' -ForegroundColor Yellow
  Write-Host '         DLSS works without it, but DLSS 5 neural rendering will not run. See README > DLSS 5 model.' -ForegroundColor Yellow
}

Write-Host 'Installing ReShade + the EldenRingDLSS add-on...'
Put-Tree (Join-Path $files 'EldenRingDLSS') $addonDir @('EldenRingDLSS.ini', 'ReShade.ini')
Write-Host 'Installing me3...'
Put-Tree (Join-Path $pack 'me3') (Join-Path $root 'me3') @()
Write-Host 'Installing OptiScaler (DLSS-NR fork) into the game folder...'
Put-Tree (Join-Path $files 'Game') $GameDir @('OptiScaler.ini')

# Products sharing the game-folder files.
$users = Join-Path $GameDir 'CrownsDLSS5_users.txt'
$list = @(if (Test-Path $users) { Get-Content $users | Where-Object { $_ } }) + 'Vanilla' | Select-Object -Unique
Set-Content $users -Value $list -Encoding UTF8

Write-Host 'Writing the me3 profile and launcher...'
$profilePath = Join-Path $root 'eldenring-dlss5.me3'
# The profile (DLSS 5 setup first, then the user's own mods) is built by Write-VanillaProfile.ps1.
& (Join-Path $pack 'Write-VanillaProfile.ps1') -GameDir $GameDir -ModsFile $ModsFile | Write-Host
$installed.Add($profilePath)

$skipSteam = if ($SkipSteamInit) { ' --skip-steam-init true' } else { '' }
$launcher = Join-Path $root 'Start_EldenRing_DLSS5.bat'
@"
@echo off
cd /d "%~dp0"
echo Launching ELDEN RING with DLSS + DLSS 5 (neural rendering)...
start .\me3\me3.exe launch --exe "$gameExe"$skipSteam -p ".\eldenring-dlss5.me3"
"@ | Set-Content -Path $launcher -Encoding ASCII
$installed.Add($launcher)

$installed | Set-Content -Path (Join-Path $root 'installed-files.txt') -Encoding UTF8
Write-Host ''
Write-Host "Done. Start the game with '$launcher' (or PLAY in Crowns DLSS Manager)." -ForegroundColor Green
Write-Host 'In game: Insert = OptiScaler / DLSS-NR menu, Home = ReShade (DLSS settings), F9 = DLSS on/off.'
