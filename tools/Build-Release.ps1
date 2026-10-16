<#
  Builds the CrownsDLSS5ER release zip for GitHub Releases.

  The repository holds scripts, patches and licences; the binaries (ReShade, the patched EldenRingDLSS add-on,
  the CrownsDLSS5ER OptiScaler build, NVIDIA DLSS runtimes, me3) are copied from -Source, a local pack folder with
  files\ and me3\. The source is only read.

  Refuses to package if NVIDIA's DLSS 5 model (nvngx_dlssnr.dll) or personal paths would end up in the zip.

  Example:  powershell -ExecutionPolicy Bypass -File tools\Build-Release.ps1 -Source "..\Crowns DLSS Manager - Elden Ring\pack" -Version 1.0.0
#>
param(
  [Parameter(Mandatory = $true)][string]$Source,
  [string]$Version = '1.0.0',
  [string[]]$Forbidden = @()   # extra strings that must not appear in any text file (e.g. your user name)
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Source = (Resolve-Path $Source).Path
$name = "CrownsDLSS5ER-v$Version"
$dist = Join-Path $repo 'dist'
$stage = Join-Path $dist $name

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

# Repository content.
foreach ($item in @('CrownsDLSSManager.ps1', 'CrownsDLSS5ER.bat',
    'README.md', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'assets', 'docs', 'licenses', 'patches', 'pack')) {
  Copy-Item (Join-Path $repo $item) $stage -Recurse -Force
}
# Binaries from the local pack (settings files are reset to the release defaults below).
Copy-Item (Join-Path $Source 'files') (Join-Path $stage 'pack\files') -Recurse -Force
Copy-Item (Join-Path $Source 'me3') (Join-Path $stage 'pack\me3') -Recurse -Force

# Never ship NVIDIA's DLSS 5 model, per-user state, or logs.
Get-ChildItem $stage -Recurse -File | Where-Object {
  $_.Name -like 'nvngx_dlssnr*.dll' -or @('config.txt', 'mods.txt', 'product.txt', 'install-paths.txt') -contains $_.Name -or $_.Extension -eq '.log'
} | Remove-Item -Force
New-Item -ItemType Directory -Force (Join-Path $stage 'pack\files\Game') | Out-Null
Set-Content (Join-Path $stage 'pack\files\Game\PUT nvngx_dlssnr.dll HERE.txt') -Encoding ASCII -Value @(
  'Put your own NVIDIA DLSS 5 model, nvngx_dlssnr.dll (310.8), in this folder before clicking Install / Repair. You have to get this file yourself.',
  'It is NVIDIA''s file and is not redistributable, so it is not included. See README.md > DLSS 5 model.'
)

# Checks.
$problems = @()
if (Get-ChildItem $stage -Recurse -File -Filter 'nvngx_dlssnr*.dll') { $problems += 'nvngx_dlssnr.dll is in the package' }
$needles = @($env:USERNAME, (Split-Path -Leaf $env:USERPROFILE)) + $Forbidden | Where-Object { $_ -and $_.Length -ge 3 } | Select-Object -Unique
foreach ($f in Get-ChildItem $stage -Recurse -File -Include *.ps1, *.bat, *.md, *.txt, *.ini, *.me3, *.patch, *.toml) {
  $text = Get-Content $f.FullName -Raw
  foreach ($n in $needles) { if ($text -and $text.IndexOf($n, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $problems += "'$n' appears in $($f.FullName.Substring($stage.Length + 1))" } }
}
foreach ($f in Get-ChildItem $stage -Recurse -File) { if ($f.Length -ge 2GB) { $problems += "$($f.Name) is over 2 GB" } }
if ($problems.Count) {
  Write-Host 'Release NOT built:' -ForegroundColor Red; $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }; exit 1
}

$zip = Join-Path $dist "$name.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash
"$sha *$name.zip" | Set-Content (Join-Path $dist "$name.zip.sha256") -Encoding ASCII
Write-Host "Built $zip  ($([math]::Round((Get-Item $zip).Length / 1MB)) MB)" -ForegroundColor Green
Write-Host "SHA-256 $sha"
