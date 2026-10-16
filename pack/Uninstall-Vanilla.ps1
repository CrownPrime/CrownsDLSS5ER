<#
  Elden Ring DLSS 5 (normal ELDEN RING) - uninstaller. Deletes <ELDEN RING>\CrownsDLSS5 and, unless another install
  product still uses them, the OptiScaler files in the game folder. The game itself is not touched.
#>
param([Parameter(Mandatory = $true)][string]$GameDir)
$ErrorActionPreference = 'Stop'

$root = Join-Path (Split-Path -Parent $GameDir) 'CrownsDLSS5'
$manifest = Join-Path $root 'installed-files.txt'
if (-not (Test-Path $manifest)) { Write-Host "ERROR: '$manifest' not found; nothing to uninstall." -ForegroundColor Red; exit 1 }
$gameExe = Join-Path $GameDir 'eldenring.exe'
if (Get-Process eldenring -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $gameExe }) {
  Write-Host 'ERROR: close ELDEN RING first.' -ForegroundColor Red; exit 1
}

# Game-folder files stay while another install still lists itself as a user.
$users = Join-Path $GameDir 'CrownsDLSS5_users.txt'
$others = @(if (Test-Path $users) { Get-Content $users | Where-Object { $_ -and $_ -ne 'Vanilla' } })
$gamePrefix = (Resolve-Path $GameDir).Path.TrimEnd('\') + '\'
foreach ($f in Get-Content $manifest | Where-Object { $_ }) {
  if ($others.Count -and $f.StartsWith($gamePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
  if (Test-Path $f) { Remove-Item $f -Force; Write-Host "  removed $f" }
}
if ($others.Count) {
  Set-Content $users -Value $others -Encoding UTF8
  Write-Host "  kept the shared OptiScaler files in the game folder (still used by: $($others -join ', '))"
} else {
  foreach ($extra in @($users, (Join-Path $GameDir 'OptiScaler.log'), (Join-Path $GameDir 'OptiScaler'))) {
    if (Test-Path $extra) { Remove-Item $extra -Recurse -Force; Write-Host "  removed $extra" }
  }
}
Remove-Item $root -Recurse -Force
Write-Host "  removed $root"
Write-Host 'Uninstalled.' -ForegroundColor Green
