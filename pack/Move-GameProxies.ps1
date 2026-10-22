<#
  Moves another ReShade or OptiScaler out of the game folder, where Windows loads it as a proxy DLL (dxgi.dll and
  the like). A second copy there stops the DLSS 5 setup's own ReShade / OptiScaler from starting, and me3 then
  loads no mods at all.

  Only files whose version info says ReShade or OptiScaler are moved, into <ELDEN RING>\CrownsDLSS5\moved-from-Game
  (listed in moved.txt). Other proxy DLLs may belong to another mod: they stay and are reported.
  -Restore puts the moved files back (Uninstall does this).
#>
param(
  [Parameter(Mandatory = $true)][string]$GameDir,
  [switch]$Restore
)
$ErrorActionPreference = 'Stop'
$store = Join-Path (Split-Path -Parent $GameDir) 'CrownsDLSS5\moved-from-Game'
$list = Join-Path $store 'moved.txt'

if ($Restore) {
  if (-not (Test-Path $list)) { return }
  foreach ($name in Get-Content $list | Where-Object { $_ }) {
    $from = Join-Path $store $name; $to = Join-Path $GameDir $name
    if (-not (Test-Path $from)) { continue }
    if (Test-Path $to) { Write-Host "  kept aside (the game folder has a new $name): $from"; continue }
    Move-Item $from $to; Write-Host "  put back $to"
  }
  return
}

$names = @('dxgi.dll', 'd3d12.dll', 'd3d11.dll', 'dinput8.dll', 'winmm.dll', 'version.dll', 'dbghelp.dll', 'wininet.dll', 'winhttp.dll')
foreach ($name in $names) {
  $f = Join-Path $GameDir $name
  if (-not (Test-Path $f)) { continue }
  $product = (Get-Item $f).VersionInfo.ProductName
  if ($product -notmatch '^(ReShade|OptiScaler)$') {
    Write-Host "WARNING: $name in the game folder ($(if ($product) { $product } else { 'unknown' })) may stop DLSS 5 from starting. Remove it if DLSS 5 does not work." -ForegroundColor Yellow
    continue
  }
  New-Item -ItemType Directory -Force $store | Out-Null
  $dest = Join-Path $store $name
  if (Test-Path $dest) { Remove-Item $dest -Force }
  Move-Item $f $dest
  if (-not (Test-Path $list) -or -not (Get-Content $list | Where-Object { $_ -eq $name })) { Add-Content $list -Value $name -Encoding UTF8 }
  Write-Host "Moved another $product ($name) out of the game folder: $dest"
}
