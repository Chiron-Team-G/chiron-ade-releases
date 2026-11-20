# Chiron ADE — one line to install it on Windows.
#
#   irm <RAW>/install.ps1 | iex                                   # production
#   $env:CHIRON_ADE_CHANNEL = "dev"; irm <RAW>/install.ps1 | iex   # the team's build
#
# WHY A SCRIPT AND NOT "DOWNLOAD THE EXE". The same reason as install.sh: one
# line the Engineers page can print, a checksum check before anything runs,
# and the right channel every time. The installer itself is NSIS, per user
# (%LOCALAPPDATA%\Programs), no admin.
#
# UNSIGNED FOR NOW (see RELEASING.md, Windows): SmartScreen shows "Windows
# protected your PC" the first time the installer runs. Click "More info" and
# then "Run anyway". A signed build (plan phase 7) removes that step and
# nothing else here changes.
#
# This script is the source of truth in the ADE repo; the copy that people
# actually run lives on `main` of the releases repo, synced by release.sh.

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Invoke-WebRequest is much faster without its progress bar

$Repo = if ($env:CHIRON_ADE_REPO) { $env:CHIRON_ADE_REPO } else { "Chiron-Team-G/chiron-ade-releases" }
$Channel = if ($env:CHIRON_ADE_CHANNEL) { $env:CHIRON_ADE_CHANNEL } else { "prod" }
if ($Channel -notin @("prod", "beta", "dev")) {
  Write-Error "Unknown channel '$Channel' (expected prod, beta or dev)."
  exit 2
}

# One app per channel, installed side by side on purpose: each talks to its own
# Engineers and keeps its own sessions, so a dev build can never answer for a
# production one. The names match electron-builder.config.cjs.
switch ($Channel) {
  "prod" { $AppName = "Chiron Studio";      $Slug = "" }
  "beta" { $AppName = "Chiron Studio Beta"; $Slug = "-beta" }
  "dev"  { $AppName = "Chiron Studio Dev";  $Slug = "-dev" }
}

function Info($m) { Write-Host "→ $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "✓ $m" -ForegroundColor Green }
function Warn($m) { Write-Host "⚠ $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "✗ $m" -ForegroundColor Red; exit 1 }

if (-not [Environment]::Is64BitOperatingSystem) {
  Fail "$AppName ships a 64-bit Windows build only; this machine is not 64-bit."
}
if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne "X64") {
  Warn "This is an $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) Windows; the x64 build runs through emulation."
}

# Production resolves through the releases page's permanent `latest` link; the
# other channels through a rolling tag that every build replaces, so there is
# exactly one of each alive and its URL never moves.
if ($Channel -eq "prod") {
  $Base = if ($env:CHIRON_ADE_RELEASES) { $env:CHIRON_ADE_RELEASES } else { "https://github.com/$Repo/releases/latest/download" }
} else {
  $Base = if ($env:CHIRON_ADE_RELEASES) { $env:CHIRON_ADE_RELEASES } else { "https://github.com/$Repo/releases/download/$Channel" }
}
$Asset = "chiron-ade$Slug-x64-win.exe"
$Tmp = Join-Path $env:TEMP "chiron-ade-$PID"
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
$Installer = Join-Path $Tmp $Asset

try {
  Info "Downloading $AppName…"
  # curl.exe ships with Windows 10 1803+ and shows progress; a silent 150 MB
  # download reads as hung. Invoke-WebRequest is the fallback.
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  $downloaded = $false
  if ($curl) {
    & curl.exe -fL --progress-bar "$Base/$Asset" -o $Installer
    $downloaded = ($LASTEXITCODE -eq 0)
  }
  if (-not $downloaded) {
    try {
      Invoke-WebRequest -Uri "$Base/$Asset" -OutFile $Installer -UseBasicParsing
      $downloaded = $true
    } catch {
      Write-Host ""
      Write-Host "There is no Windows build of $AppName on the $Channel channel yet." -ForegroundColor Red
      Write-Host "What is published: https://github.com/$Repo/releases" -ForegroundColor Red
      exit 1
    }
  }

  # Checksums are published beside the artifacts. Missing ones are not fatal —
  # an older release may predate them — but a MISMATCH always is.
  try {
    $sums = (Invoke-WebRequest -Uri "$Base/checksums.txt" -UseBasicParsing).Content
    $line = ($sums -split "`n" | Where-Object { $_ -match "(\s|\*)$([regex]::Escape($Asset))\s*$" } | Select-Object -First 1)
    if ($line) {
      $want = ($line -split "\s+")[0].ToLower()
      $got = (Get-FileHash -Algorithm SHA256 -Path $Installer).Hash.ToLower()
      if ($want -ne $got) { Fail "Checksum mismatch — the download is not what the release published. Aborting." }
      Ok "checksum verified"
    }
  } catch {
    Warn "Could not verify the checksum ($($_.Exception.Message)) — continuing."
  }

  # A running copy cannot be replaced under its own feet, and an NSIS install
  # over a running app leaves the OLD code running until it is restarted
  # (seen 2026-11-16). Ask it to close first; the installer relaunches it.
  # By process name: the executable is "<AppName>.exe". Reading every
  # process's path would throw on the protected ones under Windows PowerShell 5.
  $running = @(Get-Process -Name $AppName -ErrorAction SilentlyContinue)
  if ($running) {
    Info "Closing the running $AppName…"
    $running | ForEach-Object { $_.CloseMainWindow() | Out-Null }
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline -and @($running | Where-Object { -not $_.HasExited }).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    $running | Where-Object { -not $_.HasExited } | Stop-Process -Force -ErrorAction SilentlyContinue
  }

  # Silent, per user, then launched. If SmartScreen blocks the unsigned
  # installer the window below is where it says so.
  Info "Installing $AppName…"
  $p = Start-Process -FilePath $Installer -ArgumentList "/S" -Wait -PassThru
  if ($p.ExitCode -ne 0) { Fail "The installer exited with code $($p.ExitCode)." }
  $Exe = Join-Path $env:LOCALAPPDATA "Programs\$AppName\$AppName.exe"
  if (-not (Test-Path $Exe)) { Fail "The installer finished but $Exe is not there. Run $Installer by hand to see what it says." }
  Ok "$AppName installed at $Exe"
  Start-Process -FilePath $Exe
} finally {
  Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
