<#
  Writes -OutProfile: a copy of an overhaul mod pack's own me3 profile (The Convergence, Golden Age) with the DLSS 5
  setup added, ReShade (loads EldenRingDLSS.addon64, real DLSS in place of TAA), then OptiScaler's DLSS-NR fork, which
  hooks that DLSS call and runs the DLSS 5 model. The pack's own profile is not changed. -OutProfile must be in the
  same folder, because me3 resolves the pack's relative paths from the profile's folder.

  Uses the DLSS 5 files of the normal install (<ELDEN RING>\CrownsDLSS5, OptiScaler in Game), so Install first.
  The written profile is added to the install's manifest, so Uninstall removes it too.
#>
param(
  [Parameter(Mandatory = $true)][string]$GameDir,
  [Parameter(Mandatory = $true)][string]$BaseProfile,
  [Parameter(Mandatory = $true)][string]$OutProfile
)
$ErrorActionPreference = 'Stop'
$root = Join-Path (Split-Path -Parent $GameDir) 'CrownsDLSS5'
$manifest = Join-Path $root 'installed-files.txt'
$dlls = @((Join-Path $root 'EldenRingDLSS\ReShade64.asi'), (Join-Path $GameDir 'OptiScaler.dll'))

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $BaseProfile)) { Fail "Mod pack profile not found: $BaseProfile" }
foreach ($d in $dlls) { if (-not (Test-Path $d)) { Fail "DLSS 5 setup not installed ($d missing). Install / Repair first." } }
foreach ($d in $dlls) { if ($d.Contains("'")) { Fail "Path contains an apostrophe (') and cannot be written to the me3 profile: $d" } }
$text = [System.IO.File]::ReadAllText($BaseProfile)
# optional: if a DLSS 5 DLL fails to start, me3 still loads the pack's own mods (a failed required DLL makes me3
# drop all of them, and the game starts unmodded).
# Golden Age lists its DLLs as an inline array (natives = [ ... ]): a second natives key is a TOML error, so the
# DLSS 5 DLLs go at the front of that array. Otherwise they are added as [[natives]] tables at the end.
$array = [regex]'(?m)^[ \t]*natives[ \t]*=[ \t]*\['
if ($array.IsMatch($text)) {
  $entries = ($dlls | ForEach-Object { "{ enabled = true, optional = true, load_early = true, path = '$_' }," }) -join ' '
  $text = $array.Replace($text, [System.Text.RegularExpressions.MatchEvaluator] { param($m) "$($m.Value) $entries " }, 1)
} else {
  $text = $text.TrimEnd() + "`n`n# CrownsDLSS5ER: ReShade first (EldenRingDLSS add-on), then OptiScaler (DLSS 5).`n"
  foreach ($d in $dlls) { $text += "[[natives]]`nenabled = true`noptional = true`nload_early = true`npath = '$d'`n`n" }
}

# Another ReShade / OptiScaler loaded as a proxy DLL from the game folder makes ours fail to start.
& (Join-Path $PSScriptRoot 'Move-GameProxies.ps1') -GameDir $GameDir
[System.IO.File]::WriteAllText($OutProfile, $text)

if ((Test-Path $manifest) -and -not (Get-Content $manifest | Where-Object { $_ -eq $OutProfile })) { Add-Content $manifest -Value $OutProfile -Encoding UTF8 }
"Profile written: $OutProfile"
