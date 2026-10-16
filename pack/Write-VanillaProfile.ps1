<#
  Writes <ELDEN RING>\CrownsDLSS5\eldenring-dlss5.me3: ReShade, then OptiScaler (the DLSS 5 setup, always first),
  then the user's own mods from the mods file, in its order.

  Mods file: one mod per line, tab-separated:  on|off <TAB> package|native <TAB> full path
    package = a mod folder (replacement files: chr, parts, param, map, regulation.bin, ...)
    native  = a DLL mod
  Option line:  #savefile=<name>   use a separate save file (me3 copies the normal save the first time)
#>
param(
  [Parameter(Mandatory = $true)][string]$GameDir,
  [string]$ModsFile = ''
)
$ErrorActionPreference = 'Stop'
$root = Join-Path (Split-Path -Parent $GameDir) 'CrownsDLSS5'
$profilePath = Join-Path $root 'eldenring-dlss5.me3'

# TOML literal string: no escaping inside, so a path may not contain a single quote.
function Literal([string]$path) {
  if ($path.Contains("'")) { throw "Path contains an apostrophe (') and cannot be written to the me3 profile: $path" }
  "'$path'"
}

$mods = @(); $savefile = ''
if ($ModsFile -and (Test-Path $ModsFile)) {
  foreach ($l in Get-Content $ModsFile) {
    if ($l -match '^#savefile=([\w.\-]+)$') { $savefile = $Matches[1]; continue }
    if ($l -match "^(on|off)`t(package|native)`t(.+)$") {
      $p = $l -split "`t", 3; $mods += [pscustomobject]@{ On = $p[0] -eq 'on'; Kind = $p[1]; Path = $p[2] }
    }
  }
}

$lines = @('profileVersion = "v1"')
if ($savefile) { $lines += "savefile = `"$savefile`"" }
$lines += @(
  '', '[[supports]]', 'game = "eldenring"', '',
  '# DLSS 5 setup, always first: ReShade (loads EldenRingDLSS.addon64, real DLSS in place of TAA), then OptiScaler''s',
  '# DLSS-NR fork, which hooks that DLSS call and runs the DLSS 5 model.',
  '[[natives]]', 'enabled = true', 'load_early = true', "path = './EldenRingDLSS/ReShade64.asi'", '',
  '[[natives]]', 'enabled = true', 'load_early = true', "path = './../$(Split-Path -Leaf $GameDir)/OptiScaler.dll'"
)

$active = @($mods | Where-Object { $_.On -and (Test-Path $_.Path) })
if ($active.Count) { $lines += @('', '# Your mods (Crowns DLSS Manager > YOUR MODS), top to bottom.') }
# DLL mods load in this order after the early DLSS 5 DLLs; folder mods are chained with load_after so me3 keeps
# the list order as well.
$n = 0; $previous = ''
foreach ($m in $active) {
  if ($m.Kind -eq 'native') {
    $lines += @('', '[[natives]]', 'enabled = true', "path = $(Literal $m.Path)")
  } else {
    $n++; $id = "user-mod-$n"
    $lines += @('', '[[packages]]', "id = `"$id`"", "path = $(Literal $m.Path)")
    if ($previous) { $lines += "load_after = [{ id = `"$previous`", optional = true }]" }
    $previous = $id
  }
}

New-Item -ItemType Directory -Force $root | Out-Null
[System.IO.File]::WriteAllText($profilePath, (($lines -join "`n") + "`n"))
"Profile written: DLSS 5 setup + $($active.Count) of your mod(s)" + $(if ($savefile) { ", separate save $savefile." } else { ', normal save.' })
