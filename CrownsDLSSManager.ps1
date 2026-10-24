<#
  CrownsDLSS5ER manager for DLSS 5 in ELDEN RING: ReShade + EldenRingDLSS add-on (real
  DLSS in place of TAA) + OptiScaler DLSS-NR fork, loaded by me3. Installs, launches, tunes and diagnoses it.
  Plays the normal game (with YOUR MODS) or an overhaul mod pack that has its own me3 (The Convergence, Golden Age).
  Files come from .\pack; settings are written to the installed EldenRingDLSS.ini and OptiScaler.ini.
#>
param([string]$GameDir = '', [switch]$SelfTest, [string]$Screenshot = '')
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Pack = Join-Path $Root 'pack'
$ConfigFile = Join-Path $Root 'config.txt'
# First run: look for ELDEN RING in the Steam libraries; the user can Browse otherwise.
function Find-EldenRingGame {
  try {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) { $libs += @(Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }) }
    foreach ($l in $libs | Select-Object -Unique) {
      $g = Join-Path $l 'steamapps\common\ELDEN RING\Game'
      if (Test-Path (Join-Path $g 'eldenring.exe')) { return $g }
    }
  } catch { }
  ''
}
$DefaultGame = Find-EldenRingGame
$ProductName = 'Elden Ring'

# Overhaul mod packs that ship their own me3 and profile. PLAY runs one through its own me3, with a copy of its
# profile that adds the DLSS 5 setup (pack\Write-PackProfile.ps1). Paths are relative to the pack's folder.
# A pack with Launcher instead writes its me3 profile itself on every launch from the DLLs in its Drop folder: PLAY puts
# pack\CrownsDLSS5ER_Loader.dll there (it loads ReShade and OptiScaler from the install) and starts that launcher.
$Packs = [ordered]@{
  'The Convergence' = @{ Id = 'Convergence'; Key = 'ConvergenceDir'; Profile = 'me3\convergence.me3'; Me3 = 'me3\Windows\me3.exe'; Args = ' --skip-steam-init true'; Folder = 'the ConvergenceER folder' }
  'Golden Age' = @{ Id = 'GoldenAge'; Key = 'GoldenAgeDir'; Profile = 'Start_GoldenAge.me3'; Me3 = 'me3\bin\me3.exe'; Args = ''; Folder = 'the Golden Age folder (with Start_GoldenAge.bat)' }
  # Offline / Seamless mode only: Reforged's online mode loads only the DLLs on its server-side whitelist.
  'Reforged (ERR)' = @{ Id = 'Reforged'; Key = 'ReforgedDir'; Launcher = 'internals\launcher\ReforgedLauncher.exe'; Args = '--offline'; Drop = 'dll\offline'; Folder = 'the ELDEN RING Reforged folder (with the "Launch ELDEN RING Reforged" files)'; Experimental = $true }
}

# --- INI helpers (section-aware, keep the rest of the file and its line endings) ----------------------------

function Get-IniValue([string]$path, [string]$section, [string]$key, [string]$default) {
  if (-not (Test-Path $path)) { return $default }
  $in = $false
  foreach ($l in [System.IO.File]::ReadAllLines($path)) {
    if ($l -match '^\s*\[(.+)\]') { $in = ($Matches[1] -eq $section); continue }
    if ($in -and $l -match ('^\s*' + [regex]::Escape($key) + '\s*=\s*(.*?)\s*$')) {
      $v = $Matches[1]; if ($v -eq '' -or $v -eq 'auto') { return $default }; return $v
    }
  }
  $default
}

function Set-IniValues([string]$path, [string]$section, [hashtable]$values) {
  $text = [System.IO.File]::ReadAllText($path)
  $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.AddRange([string[]]($text -split "`r?`n"))
  $todo = @{} + $values
  $in = $false; $sectionEnd = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*\[(.+)\]') { if ($in) { $sectionEnd = $i }; $in = ($Matches[1] -eq $section); continue }
    if ($in) {
      foreach ($k in @($todo.Keys)) {
        if ($lines[$i] -match ('^\s*' + [regex]::Escape($k) + '\s*=')) {
          $sep = if ($lines[$i] -match '\s=\s') { ' = ' } else { '=' }
          $lines[$i] = "$k$sep$($todo[$k])"; $todo.Remove($k)
        }
      }
    }
  }
  if ($todo.Count) {
    $insert = @($todo.Keys | ForEach-Object { "$_=$($todo[$_])" })
    if ($in) { $lines.AddRange([string[]]$insert) }
    elseif ($sectionEnd -ge 0) { $lines.InsertRange($sectionEnd, [string[]]$insert) }
    else { $lines.Add("[$section]"); $lines.AddRange([string[]]$insert) }
  }
  [System.IO.File]::WriteAllText($path, ($lines -join $nl))
}

# --- Paths, state ------------------------------------------------------------------------------------------

function Load-Config {
  $cfg = @{ GameDir = $DefaultGame; Play = 'Elden Ring' }
  if (Test-Path $ConfigFile) {
    foreach ($l in Get-Content $ConfigFile) { if ($l -match '^(\w+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2] } }
  }
  if ($GameDir) { $cfg.GameDir = $GameDir }
  $cfg
}

function Save-Config($cfg) { $cfg.Keys | Sort-Object | ForEach-Object { "$_=$($cfg[$_])" } | Set-Content $ConfigFile -Encoding UTF8 }

# The mod pack picked under Play, or $null for the normal game.
function Get-Pack($cfg) {
  if (-not $Packs.Contains([string]$cfg.Play)) { return $null }
  $d = $Packs[[string]$cfg.Play]; $dir = [string]$cfg[$d.Key]
  $at = { param($rel) if ($dir -and $rel) { Join-Path $dir $rel } else { '' } }
  $pk = [pscustomobject]@{
    Name = [string]$cfg.Play; Id = $d.Id; Key = $d.Key; Folder = $d.Folder; Args = $d.Args; Dir = $dir
    Profile = & $at $d.Profile; Me3 = & $at $d.Me3; Launcher = & $at $d.Launcher; Drop = & $at $d.Drop
    Experimental = [bool]$d.Experimental; Found = $false
    ShortName = [string]$cfg.Play -replace ' \(.*$', ''; FolderShort = $d.Folder -replace ' \(.*$', ''
  }
  $pk.Found = [bool]$dir -and $(if ($pk.Launcher) { Test-Path $pk.Launcher } else { (Test-Path $pk.Profile) -and (Test-Path $pk.Me3) })
  $pk
}

function Get-Paths($cfg) {
  # Not chosen yet (first run without a Steam install): a placeholder path that simply does not exist.
  $game = if ($cfg.GameDir) { $cfg.GameDir } else { Join-Path $env:TEMP 'pick-the-ELDEN-RING-Game-folder\Game' }
  $r = Join-Path (Split-Path -Parent $game) 'CrownsDLSS5'
  [pscustomobject]@{
    Root = $r
    Exe = Join-Path $game 'eldenring.exe'
    OptiIni = Join-Path $game 'OptiScaler.ini'
    OptiLog = Join-Path $game 'OptiScaler.log'
    AddonDir = Join-Path $r 'EldenRingDLSS'
    AddonIni = Join-Path $r 'EldenRingDLSS\EldenRingDLSS.ini'
    ReShadeLog = Join-Path $r 'EldenRingDLSS\ReShade.log'
    Manifest = Join-Path $r 'installed-files.txt'
    Launcher = Join-Path $r 'Start_EldenRing_DLSS5.bat'
  }
}

function Test-GameRunning($p) {
  [bool](Get-Process eldenring -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -eq $p.Exe } catch { $false } })
}

function Get-StatusLines($cfg) {
  $p = Get-Paths $cfg
  $out = @()
  $out += if (Test-Path $p.Exe) { "Game:         found  (eldenring.exe $((Get-Item $p.Exe).VersionInfo.FileVersion))" } else { 'Game:         NOT FOUND - pick the folder with eldenring.exe' }
  $out += "Installs to:  ...\$(Split-Path -Leaf (Split-Path -Parent $p.Root))\CrownsDLSS5"
  $model = (Test-Path (Join-Path $Pack 'files\Game\nvngx_dlssnr.dll')) -or (Test-Path (Join-Path (Split-Path -Parent $p.Exe) 'nvngx_dlssnr.dll'))
  $out += if ($model) { 'DLSS 5 model: found' } else { 'DLSS 5 model: MISSING - add your nvngx_dlssnr.dll (README)' }
  $state = if (Test-Path $p.Manifest) { 'installed' } elseif ((Test-Path $p.Launcher) -and (Test-Path $p.AddonIni)) { 'set up by hand (Install / Repair registers it)' } else { 'not installed' }
  $out += "DLSS 5 setup: $state"
  # Proxy DLLs in the game folder: another ReShade / OptiScaler is moved aside on PLAY (pack\Move-GameProxies.ps1);
  # anything else may still stop ours from starting.
  foreach ($name in @('dxgi.dll', 'd3d12.dll', 'd3d11.dll', 'dinput8.dll', 'winmm.dll', 'version.dll', 'dbghelp.dll', 'wininet.dll', 'winhttp.dll')) {
    $f = Join-Path (Split-Path -Parent $p.Exe) $name
    if (-not (Test-Path $f)) { continue }
    $product = (Get-Item $f).VersionInfo.ProductName
    $out += if ($product -match '^(ReShade|OptiScaler)$') { "Old copy:     $name ($product) - moved aside on PLAY" } else { "WARNING:      $name in Game may block DLSS 5" }
  }
  $pk = Get-Pack $cfg
  if ($pk) {
    $out += if ($pk.Found) { "Mod pack:     $($pk.Name) found$(if ($pk.Experimental) { ' (experimental)' })" } else { "Mod pack:     $($pk.Name) NOT FOUND - pick $($pk.FolderShort)" }
  }
  if (Test-GameRunning $p) { $out += 'Game is RUNNING - close it to install or change settings.' }
  $out
}

function Get-Diagnosis($cfg) {
  $p = Get-Paths $cfg
  $out = @()
  if (-not (Test-Path $p.ReShadeLog)) { return 'No ReShade.log yet - launch the game once.' }
  $rs = Get-Content $p.ReShadeLog
  $when = (Get-Item $p.ReShadeLog).LastWriteTime.ToString('yyyy-MM-dd HH:mm')
  $out += "Last run: $when"
  $created = $rs | Where-Object { $_ -match 'Created DLSS feature' } | Select-Object -Last 1
  $out += if ($created) { 'DLSS:     ' + ($created -replace '^.*\] ', '') } else { 'DLSS:     not created (in game: Home > Add-ons > Elden Ring DLSS for its status)' }
  if ($rs | Where-Object { $_ -match 'NGX records into ReShade' }) { $out += 'NGX:      on ReShade''s command lists (crash fix active)' }
  $bad = $rs | Where-Object { $_ -match 'DLSS unavailable|DLSS disabled' } | Select-Object -Last 1
  if ($bad) { $out += 'WARNING:  ' + ($bad -replace '^.*\] ', '') }
  if (Test-Path $p.OptiLog) {
    $ol = Get-Content $p.OptiLog
    $running = $ol | Where-Object { $_ -match 'DLSS-NR reached through the game|DLSS-NR: feature created|DLSS-NR model passes' }
    $out += if ($running) { 'DLSS 5:   running (neural rendering on the DLSS output)' } else { 'DLSS 5:   not reached yet (load into the world; check that DLSS is on)' }
    $passes = $ol | Where-Object { $_ -match 'model passes: configured' } | Select-Object -Last 1
    if ($passes) { $out += 'Passes:   ' + ($passes -replace '^.*model passes: ', '') }
    $cost = $ol | Where-Object { $_ -match 'DLSS-NR elapsed: ([\d.]+) ms total' } | Select-Object -Last 1
    if ($cost -and $cost -match 'elapsed: ([\d.]+) ms total') { $out += "GPU cost: $($Matches[1]) ms per frame for DLSS 5" }
    # Not failures: present retries, fullscreen toggles, and lookups for alternative copies of the model file.
    $err = $ol | Where-Object { $_ -match '\[E\]' -and $_ -notmatch 'LocalPresent|SetFullscreenState|compatibility: equivalent' } | Select-Object -Last 1
    if ($err) { $out += 'OptiScaler error: ' + ($err -replace '^\[[^\]]+\] \[E\] ', '') }
  }
  $out -join "`r`n"
}

# --- UI ------------------------------------------------------------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Theme = @{
  Bg = [System.Drawing.Color]::FromArgb(10, 9, 8); Card = [System.Drawing.Color]::FromArgb(20, 17, 14)
  Field = [System.Drawing.Color]::FromArgb(30, 25, 19); Gold = [System.Drawing.Color]::FromArgb(212, 168, 83)
  GoldDim = [System.Drawing.Color]::FromArgb(122, 96, 48); Text = [System.Drawing.Color]::FromArgb(232, 220, 192)
  Muted = [System.Drawing.Color]::FromArgb(150, 138, 115); Hover = [System.Drawing.Color]::FromArgb(48, 38, 22)
}
$FontUi = New-Object System.Drawing.Font('Segoe UI', 9.5)
$FontCard = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$cfg = Load-Config

$form = New-Object System.Windows.Forms.Form
$form.Text = 'CrownsDLSS5ER'
$form.ClientSize = New-Object System.Drawing.Size(1000, 760)
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'; $form.BackColor = $Theme.Bg; $form.ForeColor = $Theme.Text; $form.Font = $FontUi
$iconPath = Join-Path $Root 'assets\CrownsDLSS5ER.ico'
if (Test-Path $iconPath) { $form.Icon = New-Object System.Drawing.Icon $iconPath }

# Header: the logo's black background runs into the bar, a thin gold rule underneath.
$header = New-Object System.Windows.Forms.Panel
$header.SetBounds(0, 0, 1000, 112); $header.BackColor = [System.Drawing.Color]::Black
$header.Add_Paint({ param($s, $e) $pen = New-Object System.Drawing.Pen($Theme.GoldDim, 2); $e.Graphics.DrawLine($pen, 0, $s.Height - 1, $s.Width, $s.Height - 1); $pen.Dispose() })
$logo = New-Object System.Windows.Forms.PictureBox
$logo.SetBounds(16, 6, 100, 100); $logo.SizeMode = 'Zoom'
$logoPath = Join-Path $Root 'assets\crownprime_logo_header.png'
if (Test-Path $logoPath) { $logo.Image = [System.Drawing.Image]::FromFile($logoPath) }
$title = New-Object System.Windows.Forms.Label
$title.Text = 'CrownsDLSS5ER'; $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 24)
$title.ForeColor = $Theme.Gold; $title.AutoSize = $true; $title.Location = New-Object System.Drawing.Point(126, 18)
$sub = New-Object System.Windows.Forms.Label
$sub.Text = "$($ProductName.ToUpper())   |   DLSS 5 neural rendering   |   by CrownPrime"; $sub.ForeColor = $Theme.Muted
$sub.AutoSize = $true; $sub.Location = New-Object System.Drawing.Point(131, 70)
$header.Controls.AddRange(@($logo, $title, $sub))
$form.Controls.Add($header)

function New-Card([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
  $p = New-Object System.Windows.Forms.Panel
  $p.SetBounds($x, $y, $w, $h); $p.BackColor = $Theme.Card
  $p.Add_Paint({ param($s, $e) $pen = New-Object System.Drawing.Pen($Theme.GoldDim, 1); $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1); $pen.Dispose() })
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $text.ToUpper(); $l.Font = $FontCard; $l.ForeColor = $Theme.Gold; $l.AutoSize = $true
  $l.Location = New-Object System.Drawing.Point(12, 8)
  $p.Controls.Add($l); $form.Controls.Add($p); $p
}

function New-GoldButton($parent, [string]$text, [int]$x, [int]$y, [int]$w, [int]$h = 30, [bool]$primary = $false) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $text; $b.SetBounds($x, $y, $w, $h); $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'
  $b.FlatAppearance.BorderColor = $Theme.Gold; $b.FlatAppearance.MouseOverBackColor = $Theme.Hover
  $b.FlatAppearance.MouseDownBackColor = $Theme.GoldDim
  if ($primary) { $b.BackColor = $Theme.Gold; $b.ForeColor = [System.Drawing.Color]::Black; $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(236, 196, 110); $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13) }
  else { $b.BackColor = $Theme.Field; $b.ForeColor = $Theme.Gold }
  $parent.Controls.Add($b); $b
}

function New-Label($parent, [string]$text, [int]$x, [int]$y, $color = $null) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $text; $l.AutoSize = $true; $l.Location = New-Object System.Drawing.Point($x, $y)
  $l.ForeColor = $(if ($color) { $color } else { $Theme.Text }); $l.BackColor = $Theme.Card
  $parent.Controls.Add($l); $l
}

function New-Check($parent, [string]$text, [int]$x, [int]$y) {
  $c = New-Object System.Windows.Forms.CheckBox
  $c.Text = $text; $c.AutoSize = $true; $c.Location = New-Object System.Drawing.Point($x, $y)
  $c.ForeColor = $Theme.Text; $c.BackColor = $Theme.Card; $c.FlatStyle = 'Flat'; $c.FlatAppearance.BorderColor = $Theme.Gold
  $c.FlatAppearance.CheckedBackColor = $Theme.Gold
  $parent.Controls.Add($c); $c
}

function New-Combo($parent, [string[]]$items, [int]$x, [int]$y, [int]$w) {
  $c = New-Object System.Windows.Forms.ComboBox
  $c.DropDownStyle = 'DropDownList'; $c.FlatStyle = 'Flat'; $c.BackColor = $Theme.Field; $c.ForeColor = $Theme.Text
  $c.SetBounds($x, $y, $w, 26); [void]$c.Items.AddRange($items)
  # Drawn by hand: Windows ignores a drop-down list's colours under visual styles.
  $c.DrawMode = 'OwnerDrawFixed'; $c.ItemHeight = 20
  $c.Add_DrawItem({
    param($s, $e)
    if ($e.Index -lt 0) { return }
    $selected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    $bg = New-Object System.Drawing.SolidBrush($(if ($selected) { $Theme.Hover } else { $Theme.Field }))
    $fg = New-Object System.Drawing.SolidBrush($(if ($selected) { $Theme.Gold } else { $Theme.Text }))
    $e.Graphics.FillRectangle($bg, $e.Bounds)
    $e.Graphics.DrawString([string]$s.Items[$e.Index], $s.Font, $fg, [single]($e.Bounds.X + 4), [single]($e.Bounds.Y + 2))
    $bg.Dispose(); $fg.Dispose()
  })
  $parent.Controls.Add($c); $c
}

function New-Field($parent, [int]$x, [int]$y, [int]$w) {
  $t = New-Object System.Windows.Forms.TextBox
  $t.SetBounds($x, $y, $w, 26); $t.BackColor = $Theme.Field; $t.ForeColor = $Theme.Text; $t.BorderStyle = 'FixedSingle'
  $parent.Controls.Add($t); $t
}

# Left column: setup, play, diagnostics ------------------------------------------------------------------------
$setup = New-Card 'Setup' 16 128 470 268
New-Label $setup 'Elden Ring game folder (with eldenring.exe)' 14 38 $Theme.Muted | Out-Null
$txtGame = New-Field $setup 14 58 350; $txtGame.Text = $cfg.GameDir
$btnGame = New-GoldButton $setup 'Browse' 372 56 84 28
$lblInfo = New-Label $setup 'Installs its own me3 and the ReShade add-on into a CrownsDLSS5 folder next to Game. Launches the game offline (no Easy Anti-Cheat).' 14 90 $Theme.Muted
$lblInfo.AutoSize = $false; $lblInfo.SetBounds(14, 90, 442, 36)
$lblStatus = New-Label $setup '' 14 130; $lblStatus.Font = New-Object System.Drawing.Font('Consolas', 9); $lblStatus.AutoSize = $false; $lblStatus.SetBounds(14, 130, 442, 88)
$btnInstall = New-GoldButton $setup 'Install / Repair' 14 222 214 34
$btnUninstall = New-GoldButton $setup 'Uninstall' 242 222 214 34

$play = New-Card 'Play' 16 408 470 152
New-Label $play 'Play with' 14 40 $Theme.Muted | Out-Null
$cmbPlay = New-Combo $play (@('Elden Ring') + @($Packs.Keys)) 86 36 170
$lblPlay = New-Label $play '' 266 40 $Theme.Muted
$txtPack = New-Field $play 14 70 350
$btnPack = New-GoldButton $play 'Browse' 372 68 84 28
$btnPlay = New-GoldButton $play 'PLAY ELDEN RING' 14 104 294 38 $true
$btnMods = New-GoldButton $play 'YOUR MODS' 318 104 138 38

$diag = New-Card 'Diagnostics' 16 572 470 172
$txtDiag = New-Object System.Windows.Forms.TextBox
$txtDiag.Multiline = $true; $txtDiag.ReadOnly = $true; $txtDiag.ScrollBars = 'Vertical'; $txtDiag.BorderStyle = 'None'
$txtDiag.BackColor = $Theme.Field; $txtDiag.ForeColor = $Theme.Text; $txtDiag.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$txtDiag.SetBounds(14, 36, 442, 86); $diag.Controls.Add($txtDiag)
$btnDiag = New-GoldButton $diag 'Check last run' 14 130 140
$btnRsLog = New-GoldButton $diag 'ReShade.log' 164 130 140
$btnOptiLog = New-GoldButton $diag 'OptiScaler.log' 316 130 140

# Right column: settings ---------------------------------------------------------------------------------------
$dlss = New-Card 'DLSS  (replaces the game''s TAA)' 502 128 482 236
$chkDlss = New-Check $dlss 'Use DLSS instead of the game''s TAA  (F9 in game)' 14 38
New-Label $dlss 'Preset' 14 72 $Theme.Muted | Out-Null
$cmbPreset = New-Combo $dlss @('Default (K)', 'K', 'L', 'M') 120 68 150
New-Label $dlss 'Render scale' 14 104 $Theme.Muted | Out-Null
$cmbScale = New-Combo $dlss @('DLAA - native (1.00)', 'Quality (0.67)', 'Balanced (0.58)', 'Performance (0.50)') 120 100 200
$chkSharpen = New-Check $dlss 'Game sharpening on top of DLSS' 14 136
$chkCa = New-Check $dlss 'Keep chromatic aberration' 260 136
$chkWind = New-Check $dlss 'Grass motion vectors' 14 166
$chkTrees = New-Check $dlss 'Tree motion vectors' 260 166
$chkRr = New-Check $dlss 'Ray Reconstruction (experimental)' 14 196

$nr = New-Card 'DLSS 5  (neural rendering)' 502 376 482 196
$chkNr = New-Check $nr 'Neural rendering on' 14 38
New-Label $nr 'Model passes' 14 72 $Theme.Muted | Out-Null
$cmbPasses = New-Combo $nr @('1', '2', '3') 120 68 70
New-Label $nr 'Style' 210 72 $Theme.Muted | Out-Null
$cmbStyle = New-Combo $nr @('Standard', 'Natural', 'Cinematic') 256 68 140
New-Label $nr 'Intensity' 14 110 $Theme.Muted | Out-Null
$trkIntensity = New-Object System.Windows.Forms.TrackBar
$trkIntensity.Minimum = 0; $trkIntensity.Maximum = 200; $trkIntensity.TickFrequency = 25; $trkIntensity.SmallChange = 5; $trkIntensity.LargeChange = 25
$trkIntensity.SetBounds(112, 102, 300, 40); $trkIntensity.BackColor = $Theme.Card; $nr.Controls.Add($trkIntensity)
$lblIntensity = New-Label $nr '1.00' 420 110 $Theme.Gold
$trkIntensity.Add_ValueChanged({ $lblIntensity.Text = ($trkIntensity.Value / 100).ToString('0.00') })
$lblNrHint = New-Label $nr '(Just a starting point - fine-tune it live in game with Insert.)' 14 148 $Theme.Gold
New-Label $nr 'More passes / higher intensity cost more GPU time. 1.00 = model default.' 14 170 $Theme.Muted | Out-Null

$menu = New-Card 'In-game keys' 502 584 482 108
New-Label $menu 'OptiScaler menu' 14 42 $Theme.Muted | Out-Null
New-Label $menu 'DLSS on/off' 14 76 $Theme.Muted | Out-Null
$chkSplash = New-Check $menu 'Hide startup splash' 318 40
$chkFps = New-Check $menu 'FPS counter' 318 74

# --- Hotkeys: the OptiScaler menu key ([Menu] ShortcutKey, Ctrl / Alt allowed) and the DLSS on/off key (the add-on's
# ToggleKey; DLSS 5 runs on DLSS, so it goes off too). Windows virtual-key codes. Click a key button, then press a key.
# ReShade: its overlay key (ReShade.ini KeyOverlay); Fps: OptiScaler's FPS counter key. Neither may be reused.
$KeyConf = @{ Opti = @{ Vk = 0x2D; Ctrl = $false; Alt = $false }; Dlss = @{ Vk = 0x78; Ctrl = $false; Alt = $false }; ReShade = 0x24; Fps = 0x21 }

function Get-KeyName([int]$vk) {
  $k = [System.Windows.Forms.Keys]$vk
  $names = @{ 'Prior' = 'Page Up'; 'PageUp' = 'Page Up'; 'Next' = 'Page Down'; 'PageDown' = 'Page Down'; 'Back' = 'Backspace'
    'Return' = 'Enter'; 'Capital' = 'Caps Lock'; 'CapsLock' = 'Caps Lock'
    'Scroll' = 'Scroll Lock'; 'NumLock' = 'Num Lock'; 'Oemtilde' = '`'; 'OemMinus' = '-'; 'Oemplus' = '='; 'OemOpenBrackets' = '['
    'Oem6' = ']'; 'Oem5' = '\'; 'Oem1' = ';'; 'Oem7' = "'"; 'Oemcomma' = ','; 'OemPeriod' = '.'; 'OemQuestion' = '/'
    'Multiply' = 'Num *'; 'Add' = 'Num +'; 'Subtract' = 'Num -'; 'Divide' = 'Num /'; 'Decimal' = 'Num .'; 'Pause' = 'Pause' }
  $n = [string]$k
  if ($names.ContainsKey($n)) { return $names[$n] }
  if ($n -match '^D(\d)$') { return $Matches[1] }
  if ($n -match '^NumPad(\d)$') { return "Num $($Matches[1])" }
  $n
}
function Format-Key($k) { $(if ($k.Ctrl) { 'Ctrl+' }) + $(if ($k.Alt) { 'Alt+' }) + (Get-KeyName $k.Vk) }
function Read-KeyCode([string]$text, [int]$default) {
  try { if ($text -match '^\s*0[xX]([0-9A-Fa-f]+)\s*$') { return [Convert]::ToInt32($Matches[1], 16) } elseif ($text -match '^\s*\d+\s*$') { return [int]$text } } catch { }
  $default
}

# The hints elsewhere in the window name the keys that are set.
function Update-KeyLabels {
  $btnOptiKey.Text = Format-Key $KeyConf.Opti; $btnDlssKey.Text = Format-Key $KeyConf.Dlss
  $chkDlss.Text = "Use DLSS instead of the game's TAA  ($(Format-Key $KeyConf.Dlss) in game)"
  $lblNrHint.Text = "(Just a starting point - fine-tune it live in game with $(Format-Key $KeyConf.Opti).)"
  $chkFps.Text = "FPS counter ($(Get-KeyName $KeyConf.Fps))"
}
function Get-KeysHint { "In game: $(Format-Key $KeyConf.Opti) = DLSS 5 menu, $(Get-KeyName $KeyConf.ReShade) = ReShade / DLSS, $(Format-Key $KeyConf.Dlss) = DLSS on/off." }

function New-KeyButton($parent, [int]$x, [int]$y, [string]$which, [bool]$modifiers) {
  $b = New-GoldButton $parent '' $x $y 160 30
  $b.Tag = @{ Which = $which; Modifiers = $modifiers; Capturing = $false }
  $b.Add_Click({ param($s) $s.Tag.Capturing = $true; $s.Text = 'Press a key... (Esc: cancel)' })
  # While capturing, arrow keys, Tab and Enter reach KeyDown instead of moving the focus.
  $b.Add_PreviewKeyDown({ param($s, $e) if ($s.Tag.Capturing) { $e.IsInputKey = $true } })
  $b.Add_KeyDown({
    param($s, $e)
    if (-not $s.Tag.Capturing) { return }
    $e.Handled = $true; $e.SuppressKeyPress = $true
    $code = [int]$e.KeyCode
    if (@(16, 17, 18, 91, 92) -contains $code) { return }  # Shift / Ctrl / Alt / Windows alone: wait for the key
    $s.Tag.Capturing = $false
    if ($code -eq 27) { Update-KeyLabels; return }
    $taken = @{}
    $uses = @(
      @($KeyConf.ReShade, 'the ReShade / DLSS menu'), @($KeyConf.Fps, 'the FPS counter'),
      $(if ($s.Tag.Which -eq 'Opti') { , @($KeyConf.Dlss.Vk, 'DLSS on/off') } else { , @($KeyConf.Opti.Vk, 'the OptiScaler menu') }))
    foreach ($u in $uses) { if (-not $taken.ContainsKey($u[0])) { $taken[$u[0]] = $u[1] } }
    if ($taken.ContainsKey($code)) { $txtDiag.Text = "$(Get-KeyName $code) is already used by $($taken[$code]). Pick another key."; Update-KeyLabels; return }
    $KeyConf[$s.Tag.Which] = @{ Vk = $code; Ctrl = $s.Tag.Modifiers -and $e.Control; Alt = $s.Tag.Modifiers -and $e.Alt }
    Update-KeyLabels
    $txtDiag.Text = "Key set to $(Format-Key $KeyConf[$s.Tag.Which]). Click SAVE SETTINGS to apply it."
  })
  $b.Add_Leave({ param($s) if ($s.Tag.Capturing) { $s.Tag.Capturing = $false; Update-KeyLabels } })
  $b
}
$btnOptiKey = New-KeyButton $menu 140 36 'Opti' $true
$btnDlssKey = New-KeyButton $menu 140 70 'Dlss' $false

$btnSave = New-GoldButton $form 'SAVE SETTINGS' 502 704 236 40 $true
$btnReload = New-GoldButton $form 'Reload' 748 704 236 40


# --- Your mods (normal Elden Ring) ---------------------------------------------------------------------------
$ModsFile = Join-Path $Root 'mods.txt'
$SeparateSaveName = 'ER0000.crowns'

function Read-Mods {
  if (-not (Test-Path $ModsFile)) { return @() }
  @(Get-Content $ModsFile | Where-Object { $_ -match "^(on|off)`t(package|native)`t(.+)$" } | ForEach-Object {
      $p = $_ -split "`t", 3; [pscustomobject]@{ On = $p[0] -eq 'on'; Kind = $p[1]; Path = $p[2] } })
}

function Read-SeparateSave { (Test-Path $ModsFile) -and [bool](Get-Content $ModsFile | Where-Object { $_ -like '#savefile=*' }) }

function Write-Mods($mods, [bool]$separateSave) {
  $lines = @()
  if ($separateSave) { $lines += "#savefile=$SeparateSaveName" }
  $lines += @($mods | ForEach-Object { "$(if ($_.On) { 'on' } else { 'off' })`t$($_.Kind)`t$($_.Path)" })
  Set-Content $ModsFile -Value $lines -Encoding UTF8
}

# Mods that fight this setup: other proxies / ReShade / upscalers, or a mod-pack folder instead of the mod itself.
function Get-ModWarning([string]$kind, [string]$path) {
  $name = Split-Path -Leaf $path
  if ($kind -eq 'native') {
    if (@('dxgi.dll', 'd3d12.dll', 'd3d11.dll', 'dinput8.dll', 'winmm.dll', 'version.dll', 'dbghelp.dll') -contains $name.ToLower()) {
      return "$name is a loader/proxy DLL. It is meant to sit in the game folder, not be loaded by me3, and can clash with ReShade / OptiScaler."
    }
    if ($name -match '(?i)reshade|optiscaler|erss|upscal|dlss|fsr|xess') {
      return "$name looks like a ReShade / upscaler mod. This setup already provides ReShade, DLSS and DLSS 5; a second one will clash."
    }
  } else {
    if (Get-ChildItem $path -Filter '*.me3' -File -ErrorAction SilentlyContinue) { return 'This folder contains an .me3 profile - it looks like a whole mod pack. The Convergence / Golden Age / Reforged: pick them under Play with instead (their mod folder alone leaves out their DLL mods, which breaks dodge, items and weapon switching). Other packs: pick the mod folder inside it.' }
    if (Test-Path (Join-Path $path 'config_eldenring.toml')) { return 'This is a Mod Engine 2 install. Pick its mod folder (usually "mod") instead.' }
    if (Test-Path (Join-Path $path 'eldenring.exe')) { return 'This is the game folder itself, not a mod folder.' }
  }
  ''
}

function New-InfoBox($parent, [string]$title, [int]$x, [int]$y, [int]$w, [int]$h, $border) {
  $p = New-Object System.Windows.Forms.Panel
  $p.SetBounds($x, $y, $w, $h); $p.BackColor = $Theme.Card
  $p.Tag = $border
  $p.Add_Paint({ param($s, $e) $pen = New-Object System.Drawing.Pen($s.Tag, 1); $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1); $pen.Dispose() })
  $t = New-Object System.Windows.Forms.Label
  $t.Text = $title; $t.Font = $FontCard; $t.ForeColor = $border; $t.BackColor = $Theme.Card; $t.AutoSize = $true
  $t.Location = New-Object System.Drawing.Point(12, 8)
  $body = New-Object System.Windows.Forms.Label
  $body.ForeColor = $Theme.Text; $body.BackColor = $Theme.Card; $body.SetBounds(12, 32, $w - 24, $h - 40)
  $p.Controls.AddRange(@($t, $body)); $parent.Controls.Add($p)
  $body
}

function Show-ModsDialog {
  $amber = [System.Drawing.Color]::FromArgb(224, 140, 60)
  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = 'Your mods - Crowns DLSS Manager'; $dlg.ClientSize = New-Object System.Drawing.Size(960, 700)
  $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false; $dlg.StartPosition = 'CenterParent'
  $dlg.BackColor = $Theme.Bg; $dlg.ForeColor = $Theme.Text; $dlg.Font = $FontUi; $dlg.Icon = $form.Icon

  $head = New-Object System.Windows.Forms.Label
  $head.Text = 'YOUR MODS'; $head.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16); $head.ForeColor = $Theme.Gold
  $head.AutoSize = $true; $head.Location = New-Object System.Drawing.Point(14, 10)
  $intro = New-Object System.Windows.Forms.Label
  $intro.Text = 'Your own Elden Ring mods, running on top of DLSS 5. They stay in their own folders - me3 just loads them from there.'
  $intro.ForeColor = $Theme.Muted; $intro.SetBounds(16, 44, 930, 20)

  # Load order banner.
  $banner = New-Object System.Windows.Forms.Panel
  $banner.SetBounds(16, 70, 928, 54); $banner.BackColor = [System.Drawing.Color]::FromArgb(36, 28, 14)
  $banner.Add_Paint({ param($s, $e) $pen = New-Object System.Drawing.Pen($Theme.Gold, 2); $e.Graphics.DrawRectangle($pen, 1, 1, $s.Width - 2, $s.Height - 2); $pen.Dispose() })
  $bTitle = New-Object System.Windows.Forms.Label
  $bTitle.Text = "LOAD ORDER:   TOP   $([char]0x2192)   BOTTOM"; $bTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
  $bTitle.ForeColor = $Theme.Gold; $bTitle.BackColor = $banner.BackColor; $bTitle.AutoSize = $true; $bTitle.Location = New-Object System.Drawing.Point(12, 13)
  $bText = New-Object System.Windows.Forms.Label
  $bText.Text = 'Row 1 loads first, then row 2, and so on. The DLSS 5 setup is always rows 1 and 2 (locked). Use Move up / Move down to change the order of your mods.'
  $bText.ForeColor = $Theme.Text; $bText.BackColor = $banner.BackColor; $bText.SetBounds(330, 8, 588, 40)
  $banner.Controls.AddRange(@($bTitle, $bText))

  $lv = New-Object System.Windows.Forms.ListView
  $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.HideSelection = $false
  $lv.BackColor = $Theme.Field; $lv.ForeColor = $Theme.Text; $lv.BorderStyle = 'FixedSingle'; $lv.SetBounds(16, 134, 780, 262)
  [void]$lv.Columns.Add('Load order', 84); [void]$lv.Columns.Add('Type', 92); [void]$lv.Columns.Add('Mod', 220); [void]$lv.Columns.Add('Location', 362)
  $lv.OwnerDraw = $true
  $lv.Add_DrawColumnHeader({
    param($s, $e)
    $bg = New-Object System.Drawing.SolidBrush($Theme.Card); $fg = New-Object System.Drawing.SolidBrush($Theme.Gold)
    $e.Graphics.FillRectangle($bg, $e.Bounds)
    $e.Graphics.DrawString($e.Header.Text, $FontUi, $fg, [single]($e.Bounds.X + 4), [single]($e.Bounds.Y + 3))
    $bg.Dispose(); $fg.Dispose()
  })
  $lv.Add_DrawItem({ param($s, $e) $e.DrawDefault = $true })
  $lv.Add_DrawSubItem({ param($s, $e) $e.DrawDefault = $true })

  $details = New-InfoBox $dlg 'SELECTED' 16 404 928 92 $Theme.GoldDim
  $details.Text = 'Select a row to see what it is.'
  $caution = New-InfoBox $dlg 'CAUTION' 16 504 928 136 $amber
  $caution.Text = @(
    '-  Offline only: the game runs without Easy Anti-Cheat. Never take modded play online (Seamless Co-op is fine - it uses its own servers).',
    '-  Back up your save first: %APPDATA%\EldenRing. Mods that change items, params or maps can break a save - or tick "separate save" below.',
    '-  Do not add another ReShade, DLSS / upscaler mod, or loader files such as dxgi.dll / dinput8.dll - they clash with DLSS 5.',
    '-  Two mods that change the same files conflict: keep only one of them, or follow the mods'' own load-order instructions.',
    '-  Some mods need a specific game version. This setup is for eldenring.exe 2.7.0 / 2.7.1.'
  ) -join "`r`n"

  $chkSave = New-Object System.Windows.Forms.CheckBox
  $chkSave.Text = "Use a separate save for modded play ($SeparateSaveName). The first time, me3 copies your normal save; your normal save is never touched."
  $chkSave.ForeColor = $Theme.Text; $chkSave.BackColor = $Theme.Bg; $chkSave.FlatStyle = 'Flat'; $chkSave.FlatAppearance.BorderColor = $Theme.Gold
  $chkSave.SetBounds(16, 650, 640, 40); $chkSave.Checked = Read-SeparateSave

  $describe = {
    if (-not $lv.SelectedItems.Count) { $details.Text = 'Select a row to see what it is.'; return }
    $tag = $lv.SelectedItems[0].Tag
    $details.Text = if ($tag.Locked) { $tag.Info }
      elseif ($tag.Kind -eq 'native') {
        $w = Get-ModWarning 'native' $tag.Path
        "DLL mod - code loaded into the game at startup (e.g. ERFPS2 first person, Seamless Co-op, UI mods). Loads after the DLSS 5 setup, in this list's order. Check the mod's page for its own settings file and requirements." + $(if ($w) { "`r`nWARNING: $w" } elseif (-not (Test-Path $tag.Path)) { "`r`nMISSING: this file no longer exists - it is skipped." } else { '' })
      } else {
        $w = Get-ModWarning 'package' $tag.Path
        "Folder mod - replaces game files (models, textures, maps, params, regulation.bin). If two folder mods replace the same file they conflict; only one version can be used." + $(if ($w) { "`r`nWARNING: $w" } elseif (-not (Test-Path $tag.Path)) { "`r`nMISSING: this folder no longer exists - it is skipped." } else { '' })
      }
  }
  $renumber = { for ($i = 0; $i -lt $lv.Items.Count; $i++) { $lv.Items[$i].Text = [string]($i + 1) } }
  $addItem = {
    param($on, $kind, $path, $locked = $false, $name = '', $info = '')
    $it = New-Object System.Windows.Forms.ListViewItem('')
    [void]$it.SubItems.Add($(if ($locked) { 'DLSS 5 setup' } elseif ($kind -eq 'native') { 'DLL mod' } else { 'Folder mod' }))
    [void]$it.SubItems.Add($(if ($name) { $name } else { Split-Path -Leaf $path })); [void]$it.SubItems.Add($path)
    $it.Tag = [pscustomobject]@{ Kind = $kind; Path = $path; Locked = $locked; Info = $info }; $it.Checked = $on
    if ($locked) { $it.ForeColor = $Theme.Gold }
    elseif (-not (Test-Path $path)) { $it.ForeColor = $Theme.Muted; $it.SubItems[2].Text += '  (missing)' }
    [void]$lv.Items.Add($it); & $renumber
  }
  & $addItem $true 'native' 'CrownsDLSS5\EldenRingDLSS\ReShade64.asi' $true 'ReShade + DLSS (always first)' 'DLSS 5 setup, part 1 (locked): ReShade 6.8 with the EldenRingDLSS add-on. It replaces the game''s anti-aliasing with real NVIDIA DLSS, which DLSS 5 needs. Always loads first.'
  & $addItem $true 'native' 'Game\OptiScaler.dll' $true 'OptiScaler + DLSS 5 (always second)' 'DLSS 5 setup, part 2 (locked): OptiScaler (DLSS-NR fork). It takes the DLSS image and runs NVIDIA''s DLSS 5 neural rendering on it. Always loads second. Settings: ' + (Format-Key $KeyConf.Opti) + ' in game.'
  foreach ($m in Read-Mods) { & $addItem $m.On $m.Kind $m.Path }
  $lockedCount = 2

  # The two DLSS 5 rows stay ticked.
  $lv.Add_ItemCheck({ param($s, $e) if ($s.Items[$e.Index].Tag.Locked) { $e.NewValue = [System.Windows.Forms.CheckState]::Checked } })
  $lv.Add_SelectedIndexChanged($describe)

  $status = New-Object System.Windows.Forms.Label
  $status.ForeColor = $Theme.Gold; $status.BackColor = $Theme.Bg; $status.SetBounds(810, 330, 136, 66)

  $bFolder = New-GoldButton $dlg 'Add mod folder' 810 134 134 32
  $bDll = New-GoldButton $dlg 'Add DLL mod' 810 172 134 32
  $bRemove = New-GoldButton $dlg 'Remove' 810 216 134 32
  $bUp = New-GoldButton $dlg 'Move up' 810 260 134 32
  $bDown = New-GoldButton $dlg 'Move down' 810 296 134 32
  $bSave = New-GoldButton $dlg 'SAVE' 808 648 136 40 $true
  $bCancel = New-GoldButton $dlg 'Cancel' 664 652 132 34

  $tryAdd = {
    param($kind, $path)
    if ($path.Contains([string][char]39)) { $status.Text = 'Path has an apostrophe - me3 cannot use it. Rename the folder.'; return }
    foreach ($it in $lv.Items) { if ($it.Tag.Path -eq $path) { $status.Text = 'Already in the list.'; return } }
    $warn = Get-ModWarning $kind $path
    if ($warn) {
      $r = [System.Windows.Forms.MessageBox]::Show("$warn`r`n`r`nAdd it anyway?", 'Your mods', 'YesNo', 'Warning')
      if ($r -ne 'Yes') { return }
    }
    & $addItem $true $kind $path
    $lv.Items[$lv.Items.Count - 1].Selected = $true
    $status.Text = "Added. It loads last (row $($lv.Items.Count)). Click SAVE to apply."
  }
  $bFolder.Add_Click({
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Pick a mod folder - the one that contains chr / parts / param / regulation.bin ...'
    if ($fb.ShowDialog() -eq 'OK') { & $tryAdd 'package' $fb.SelectedPath }
  })
  $bDll.Add_Click({
    $of = New-Object System.Windows.Forms.OpenFileDialog; $of.Filter = 'DLL mod (*.dll)|*.dll'; $of.Title = 'Pick a DLL mod'
    if ($of.ShowDialog() -eq 'OK') { & $tryAdd 'native' $of.FileName }
  })
  $bRemove.Add_Click({
    if (-not $lv.SelectedItems.Count) { return }
    if ($lv.SelectedItems[0].Tag.Locked) { $status.Text = 'The DLSS 5 setup cannot be removed here.'; return }
    $lv.Items.Remove($lv.SelectedItems[0]); & $renumber; $status.Text = 'Removed. Click SAVE to apply.'
  })
  $move = {
    param($d)
    if (-not $lv.SelectedItems.Count) { return }
    $it = $lv.SelectedItems[0]
    if ($it.Tag.Locked) { $status.Text = 'The DLSS 5 setup always loads first.'; return }
    $i = $it.Index; $j = $i + $d
    if ($j -lt $lockedCount -or $j -ge $lv.Items.Count) { return }
    $lv.Items.RemoveAt($i); $lv.Items.Insert($j, $it); $it.Selected = $true; & $renumber
    $status.Text = "Now row $($j + 1). Click SAVE to apply."
  }
  $bUp.Add_Click({ & $move -1 })
  $bDown.Add_Click({ & $move 1 })
  $bCancel.Add_Click({ $dlg.Close() })
  $bSave.Add_Click({
    try {
      $mods = @($lv.Items | Where-Object { -not $_.Tag.Locked } | ForEach-Object { [pscustomobject]@{ On = $_.Checked; Kind = $_.Tag.Kind; Path = $_.Tag.Path } })
      Write-Mods $mods $chkSave.Checked
      $p = Get-Paths $cfg
      # Installed: rewrite the me3 profile now. Not installed yet: the list is used by Install.
      $msg = if (Test-Path $p.Manifest) {
        & (Join-Path $Pack 'Write-VanillaProfile.ps1') -GameDir $cfg.GameDir -ModsFile $ModsFile
      } else { 'Saved. Your mods are added when you Install.' }
      $on = @($mods | Where-Object { $_.On }).Count
      $txtDiag.Text = "Your mods: $on enabled of $($mods.Count), loading top to bottom after the DLSS 5 setup.`r`n$msg"
      $btnMods.Text = "YOUR MODS ($on)"
      $dlg.Close()
    } catch { $status.Text = "ERROR: $($_.Exception.Message)" }
  })
  $dlg.Controls.AddRange(@($head, $intro, $banner, $lv, $status, $chkSave))
  [void]$dlg.ShowDialog($form)
}

# --- Bind settings ---------------------------------------------------------------------------------------------
$presetMap = @{ '0' = 0; '11' = 1; '12' = 2; '13' = 3 }; $presetBack = @('0', '11', '12', '13')
$scaleBack = @('1.00', '0.67', '0.58', '0.50')

function Read-Settings {
  $p = Get-Paths $cfg
  $chkDlss.Checked = (Get-IniValue $p.AddonIni 'EldenRingDLSS' 'Enabled' '1') -eq '1'
  $pv = Get-IniValue $p.AddonIni 'EldenRingDLSS' 'Preset' '0'; $cmbPreset.SelectedIndex = $(if ($presetMap.ContainsKey($pv)) { $presetMap[$pv] } else { 0 })
  $sv = [double](Get-IniValue $p.AddonIni 'EldenRingDLSS' 'RenderScale' '1.00')
  $cmbScale.SelectedIndex = $(if ($sv -ge 0.9) { 0 } elseif ($sv -ge 0.62) { 1 } elseif ($sv -ge 0.54) { 2 } else { 3 })
  $chkSharpen.Checked = (Get-IniValue $p.AddonIni 'EldenRingDLSS' 'GameSharpening' '0') -eq '1'
  $chkCa.Checked = (Get-IniValue $p.AddonIni 'EldenRingDLSS' 'ChromaticAberration' '1') -eq '1'
  $chkWind.Checked = (Get-IniValue $p.AddonIni 'EldenRingDLSS' 'WindMotion' '1') -eq '1'
  $chkTrees.Checked = (Get-IniValue $p.AddonIni 'EldenRingDLSS' 'WindTrees' '1') -eq '1'
  $chkRr.Checked = (Get-IniValue $p.AddonIni 'EldenRingDLSS' 'RayReconstruction' '0') -eq '1'
  $chkNr.Checked = (Get-IniValue $p.OptiIni 'DlssNr' 'Enabled' 'false') -eq 'true'
  $passes = Get-IniValue $p.OptiIni 'DlssNr' 'Passes' '1'; $cmbPasses.SelectedIndex = [Math]::Max(0, [Math]::Min(2, [int]$passes - 1))
  $cmbStyle.SelectedIndex = [Math]::Max(0, [Math]::Min(2, [int](Get-IniValue $p.OptiIni 'DlssNr' 'Style' '0')))
  $trkIntensity.Value = [Math]::Max(0, [Math]::Min(200, [int]([double](Get-IniValue $p.OptiIni 'DlssNr' 'Intensity' '1.0') * 100)))
  $lblIntensity.Text = ($trkIntensity.Value / 100).ToString('0.00')
  $KeyConf.Opti = @{
    Vk = Read-KeyCode (Get-IniValue $p.OptiIni 'Menu' 'ShortcutKey' '0x2D') 0x2D
    Ctrl = (Get-IniValue $p.OptiIni 'Menu' 'ShortcutKeyRequireCtrl' 'false') -eq 'true'
    Alt = (Get-IniValue $p.OptiIni 'Menu' 'ShortcutKeyRequireAlt' 'false') -eq 'true'
  }
  $KeyConf.Dlss = @{ Vk = Read-KeyCode (Get-IniValue $p.AddonIni 'EldenRingDLSS' 'ToggleKey' '120') 0x78; Ctrl = $false; Alt = $false }
  $rsIni = Join-Path $p.AddonDir 'ReShade.ini'
  $KeyConf.ReShade = if ((Test-Path $rsIni) -and ((Get-Content $rsIni -Raw) -match '(?m)^KeyOverlay=(\d+)')) { [int]$Matches[1] } else { 0x24 }
  $KeyConf.Fps = Read-KeyCode (Get-IniValue $p.OptiIni 'Menu' 'FpsShortcutKey' '0x21') 0x21
  Update-KeyLabels
  $chkSplash.Checked = (Get-IniValue $p.OptiIni 'Menu' 'DisableSplash' 'false') -eq 'true'
  $chkFps.Checked = (Get-IniValue $p.OptiIni 'Menu' 'ShowFps' 'false') -eq 'true'
}

function Write-Settings {
  $p = Get-Paths $cfg
  if (Test-GameRunning $p) { throw 'Close Elden Ring first - the game rewrites these files while it runs.' }
  if (-not (Test-Path $p.AddonIni) -or -not (Test-Path $p.OptiIni)) { throw 'Install first.' }
  $b = { param($v) if ($v) { '1' } else { '0' } }
  $t = { param($v) if ($v) { 'true' } else { 'false' } }
  Set-IniValues $p.AddonIni 'EldenRingDLSS' @{
    Enabled = (& $b $chkDlss.Checked); Preset = $presetBack[$cmbPreset.SelectedIndex]; RenderScale = $scaleBack[$cmbScale.SelectedIndex]
    GameSharpening = (& $b $chkSharpen.Checked); ChromaticAberration = (& $b $chkCa.Checked)
    WindMotion = (& $b $chkWind.Checked); WindTrees = (& $b $chkTrees.Checked); RayReconstruction = (& $b $chkRr.Checked)
    ToggleKey = [string]$KeyConf.Dlss.Vk
  }
  Set-IniValues $p.OptiIni 'DlssNr' @{
    Enabled = (& $t $chkNr.Checked); Passes = [string]($cmbPasses.SelectedIndex + 1); Style = [string]$cmbStyle.SelectedIndex
    Intensity = ($trkIntensity.Value / 100).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
  }
  Set-IniValues $p.OptiIni 'Menu' @{
    ShortcutKey = '0x{0:X2}' -f $KeyConf.Opti.Vk; ShortcutKeyRequireCtrl = (& $t $KeyConf.Opti.Ctrl); ShortcutKeyRequireAlt = (& $t $KeyConf.Opti.Alt)
    DisableSplash = (& $t $chkSplash.Checked); ShowFps = (& $t $chkFps.Checked)
  }
  'Settings saved. They apply the next time you start the game.'
}

function Update-PlayUi {
  $pk = Get-Pack $cfg
  $txtPack.Enabled = [bool]$pk; $btnPack.Enabled = [bool]$pk; $btnMods.Enabled = -not $pk
  $txtPack.Text = if ($pk) { $pk.Dir } else { '' }
  $lblPlay.Text = if ($pk.Launcher) { 'offline / Seamless only' } elseif ($pk) { 'its own mods and save' } else { 'normal game + YOUR MODS' }
  $btnPlay.Text = if ($pk) { "PLAY $($pk.Name.ToUpper())" } else { 'PLAY ELDEN RING' }
}

function Refresh-All {
  $cfg.GameDir = $txtGame.Text.Trim()
  $pk = Get-Pack $cfg; if ($pk) { $cfg[$pk.Key] = $txtPack.Text.Trim() }
  $lblStatus.Text = (Get-StatusLines $cfg) -join "`r`n"
  try { Read-Settings } catch { $txtDiag.Text = "Could not read settings: $($_.Exception.Message)" }
}

function Run([scriptblock]$action) {
  $form.Cursor = 'WaitCursor'
  try { $msg = & $action; if ($msg) { $txtDiag.Text = ($msg | Out-String).Trim() } }
  catch { $txtDiag.Text = "ERROR: $($_.Exception.Message)" }
  finally { $form.Cursor = 'Default'; $lblStatus.Text = (Get-StatusLines $cfg) -join "`r`n" }
}

function Pick-Folder([System.Windows.Forms.TextBox]$box, [string]$desc) {
  $d = New-Object System.Windows.Forms.FolderBrowserDialog
  $d.Description = $desc; if ($box.Text.Trim() -and (Test-Path $box.Text)) { $d.SelectedPath = $box.Text }
  if ($d.ShowDialog() -eq 'OK') { $box.Text = $d.SelectedPath; Refresh-All; Save-Config $cfg }
}

$btnGame.Add_Click({ Pick-Folder $txtGame 'Pick the Elden Ring folder that contains eldenring.exe' })
$txtGame.Add_Leave({ Refresh-All; Save-Config $cfg })
$btnPack.Add_Click({ Pick-Folder $txtPack "Pick $((Get-Pack $cfg).Folder)" })
$txtPack.Add_Leave({ Refresh-All; Save-Config $cfg })
$cmbPlay.SelectedIndex = [Math]::Max(0, $cmbPlay.Items.IndexOf([string]$cfg.Play))
$cmbPlay.Add_SelectedIndexChanged({ $cfg.Play = [string]$cmbPlay.SelectedItem; Update-PlayUi; Refresh-All; Save-Config $cfg })

$btnInstall.Add_Click({
  Run {
    $p = Get-Paths $cfg
    if (Test-GameRunning $p) { throw 'Close Elden Ring first.' }
    $installArgs = @('-File', (Join-Path $Pack 'Install-Vanilla.ps1'), '-GameDir', $cfg.GameDir, '-ModsFile', $ModsFile)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass @installArgs 2>&1 | Out-String
    if ($LASTEXITCODE) { throw $out.Trim() }
    Save-Config $cfg; Read-Settings
    "Installed. Your existing settings were kept.`r`n`r`n" + $out.Trim()
  }
})
$btnUninstall.Add_Click({
  $r = [System.Windows.Forms.MessageBox]::Show('Remove the DLSS 5 setup (and its settings) from Elden Ring? The game itself stays.', 'CrownsDLSS5ER', 'YesNo', 'Question')
  if ($r -ne 'Yes') { return }
  Run {
    $uninstallArgs = @('-File', (Join-Path $Pack 'Uninstall-Vanilla.ps1'), '-GameDir', $cfg.GameDir)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass @uninstallArgs 2>&1 | Out-String
    if ($LASTEXITCODE) { throw $out.Trim() }
    $out.Trim()
  }
})
$btnPlay.Add_Click({
  Run {
    $p = Get-Paths $cfg
    if (-not (Test-Path $p.Launcher)) { throw 'Install first.' }
    $moved = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Pack 'Move-GameProxies.ps1') -GameDir $cfg.GameDir 2>&1 | Out-String
    $pk = Get-Pack $cfg
    if (-not $pk) {
      Start-Process -FilePath $p.Launcher -WorkingDirectory $p.Root
      if ($moved.Trim()) { return "$($moved.Trim())`r`nStarting $ProductName with DLSS 5..." }
      return "Starting $ProductName with DLSS 5...`r`n$(Get-KeysHint)"
    }
    if (-not $pk.Found) { throw "$($pk.Name) not found. Pick $($pk.Folder)." }
    if ($pk.Experimental) {
      $r = [System.Windows.Forms.MessageBox]::Show(
        "$($pk.Name) support is experimental and may not work yet.`r`n`r`n" +
        "It runs in $($pk.ShortName)'s offline / Seamless mode only. Its online mode allows only its own approved DLLs, so DLSS 5 cannot run there.`r`n`r`n" +
        "If it doesn't work, contact CrownPrime on Discord: crownprime`r`n`r`nContinue?",
        'CrownsDLSS5ER - experimental', 'OKCancel', 'Warning')
      if ($r -ne 'OK') { return 'Cancelled.' }
    }
    if ($pk.Launcher) {
      # The pack's launcher builds its me3 profile from every DLL in its Drop folder: the loader goes there, with the
      # list of DLLs to load from this install (ReShade first, then OptiScaler). Uninstall removes all three files.
      $loader = Join-Path $Pack 'CrownsDLSS5ER_Loader.dll'
      if (-not (Test-Path $loader)) { throw 'pack\CrownsDLSS5ER_Loader.dll is missing. Extract the whole release zip again.' }
      $dlls = @((Join-Path $p.AddonDir 'ReShade64.asi'), (Join-Path (Split-Path -Parent $p.Exe) 'OptiScaler.dll'))
      foreach ($d in $dlls) { if (-not (Test-Path $d)) { throw "DLSS 5 setup not installed ($d missing). Install / Repair first." } }
      New-Item -ItemType Directory -Force $pk.Drop | Out-Null
      Copy-Item $loader $pk.Drop -Force
      $list = Join-Path $pk.Drop 'CrownsDLSS5ER_Loader.txt'
      [System.IO.File]::WriteAllLines($list, [string[]]@('# CrownsDLSS5ER: loaded in this order by CrownsDLSS5ER_Loader.dll') + $dlls)
      foreach ($f in @('CrownsDLSS5ER_Loader.dll', 'CrownsDLSS5ER_Loader.txt', 'CrownsDLSS5ER_Loader.log')) {
        $f = Join-Path $pk.Drop $f
        if (-not (Get-Content $p.Manifest | Where-Object { $_ -eq $f })) { Add-Content $p.Manifest -Value $f -Encoding UTF8 }
      }
      Start-Process -FilePath $pk.Launcher -ArgumentList $pk.Args -WorkingDirectory $pk.Dir
      return $(if ($moved.Trim()) { "$($moved.Trim())`r`n" }) + "Starting $($pk.Name) in offline mode with DLSS 5 (experimental). Its launcher may show its own steps first.`r`n" +
        "If DLSS 5 does not start: $(Join-Path $pk.Drop 'CrownsDLSS5ER_Loader.log') says what was loaded.`r`n$(Get-KeysHint)"
    }
    # The launcher rewrites the pack profile copy each time (the pack may have been updated), then starts the pack's
    # own me3 with it. It stays open with the error if either step fails.
    Copy-Item (Join-Path $Pack 'Write-PackProfile.ps1'), (Join-Path $Pack 'Move-GameProxies.ps1') $p.Root -Force
    $merged = Join-Path (Split-Path -Parent $pk.Profile) ([System.IO.Path]::GetFileNameWithoutExtension($pk.Profile) + ' - CrownsDLSS5.me3')
    $launcher = Join-Path $p.Root "Start_$($pk.Id)_DLSS5.bat"
    @"
@echo off
cd /d "$($pk.Dir)"
echo Launching $($pk.Name) with DLSS + DLSS 5 (neural rendering)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Write-PackProfile.ps1" -GameDir "$($cfg.GameDir)" -BaseProfile "$($pk.Profile)" -OutProfile "$merged"
if errorlevel 1 goto :failed
"$($pk.Me3)" launch --exe "$($p.Exe)"$($pk.Args) --profile "$merged"
if errorlevel 1 goto :failed
exit /b 0
:failed
echo.
pause
exit /b 1
"@ | Set-Content -Path $launcher -Encoding ASCII
    if (-not (Get-Content $p.Manifest | Where-Object { $_ -eq $launcher })) { Add-Content $p.Manifest -Value $launcher -Encoding UTF8 }
    Start-Process -FilePath $launcher -WorkingDirectory $pk.Dir
    $(if ($moved.Trim()) { "$($moved.Trim())`r`n" }) + "Starting $($pk.Name) with DLSS 5 (its own mods and save, through its own me3)...`r`n$(Get-KeysHint)"
  }
})
$btnDiag.Add_Click({ Run { Get-Diagnosis $cfg } })
$btnMods.Add_Click({ Show-ModsDialog })
$btnMods.Text = "YOUR MODS ($(@(Read-Mods | Where-Object { $_.On }).Count))"
$btnRsLog.Add_Click({ $p = Get-Paths $cfg; if (Test-Path $p.ReShadeLog) { Start-Process notepad.exe $p.ReShadeLog } else { $txtDiag.Text = 'No ReShade.log yet.' } })
$btnOptiLog.Add_Click({ $p = Get-Paths $cfg; if (Test-Path $p.OptiLog) { Start-Process notepad.exe $p.OptiLog } else { $txtDiag.Text = 'No OptiScaler.log yet.' } })
$btnSave.Add_Click({ Run { Write-Settings } })
$btnReload.Add_Click({ Refresh-All; $txtDiag.Text = 'Settings reloaded from the game files.' })

Update-PlayUi
Refresh-All
$txtDiag.Text = try { Get-Diagnosis $cfg } catch { '' }
if ($SelfTest) { $form.Dispose(); 'GUI built OK'; return }
if ($Screenshot) {
  $form.Show(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 300; [System.Windows.Forms.Application]::DoEvents()
  $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
  $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height))); $bmp.Save($Screenshot); $form.Close(); return
}
[void]$form.ShowDialog()
