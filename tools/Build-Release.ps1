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
foreach ($item in @('CrownsDLSSManager.ps1',
    'README.md', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'assets', 'docs', 'licenses', 'patches', 'pack')) {
  Copy-Item (Join-Path $repo $item) $stage -Recurse -Force
}

# CrownsDLSS5ER.exe: the launcher (tools\Launcher.cs) with the icon and this version, compiled with the C# compiler
# that ships with Windows (.NET Framework 4).
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "C# compiler not found: $csc" }
$info = Join-Path $dist 'LauncherInfo.cs'
@(
  'using System.Reflection;'
  '[assembly: AssemblyTitle("CrownsDLSS5ER")]'
  '[assembly: AssemblyDescription("Opens the CrownsDLSS5ER manager")]'
  '[assembly: AssemblyProduct("CrownsDLSS5ER")]'
  '[assembly: AssemblyCompany("CrownPrime")]'
  "[assembly: AssemblyVersion(`"$Version.0`")]"
  "[assembly: AssemblyFileVersion(`"$Version.0`")]"
) | Set-Content $info -Encoding UTF8
& $csc /nologo /target:winexe /platform:anycpu /optimize+ /reference:System.Windows.Forms.dll `
  "/win32icon:$(Join-Path $repo 'assets\CrownsDLSS5ER.ico')" "/out:$(Join-Path $stage 'CrownsDLSS5ER.exe')" `
  (Join-Path $repo 'tools\Launcher.cs') $info
if ($LASTEXITCODE) { throw 'Compiling CrownsDLSS5ER.exe failed.' }
Remove-Item $info

# pack\CrownsDLSS5ER_Loader.dll (tools\Loader.cpp), for mod packs whose own launcher builds the me3 profile
# (Reforged), compiled with the Visual Studio C++ tools.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = if (Test-Path $vswhere) { & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath }
if (-not $vs) { throw 'Visual Studio C++ tools not found (needed for CrownsDLSS5ER_Loader.dll).' }
$obj = Join-Path $dist 'loader-obj'
New-Item -ItemType Directory -Force $obj | Out-Null
cmd /c "`"$vs\VC\Auxiliary\Build\vcvars64.bat`" >nul 2>&1 && cl /nologo /LD /O2 /MT /W4 `"$(Join-Path $repo 'tools\Loader.cpp')`" /Fe:`"$(Join-Path $stage 'pack\CrownsDLSS5ER_Loader.dll')`" /Fo:`"$obj\\`" /link /NOLOGO user32.lib kernel32.lib" | Out-Null
if ($LASTEXITCODE -or -not (Test-Path (Join-Path $stage 'pack\CrownsDLSS5ER_Loader.dll'))) { throw 'Compiling CrownsDLSS5ER_Loader.dll failed.' }
Remove-Item $obj -Recurse -Force
Get-ChildItem (Join-Path $stage 'pack') -Filter 'CrownsDLSS5ER_Loader.*' | Where-Object { $_.Extension -ne '.dll' } | Remove-Item
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
