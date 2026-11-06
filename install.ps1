# Umbra Setup for Windows (ADR 0042): one command from PowerShell to a ready WSL distro.
#
#   irm https://raw.githubusercontent.com/Robertcl795/umbra-bootstrapper/main/install.ps1 | iex
#
# A thin driver: every install step is install.sh inside the distro. This script only calls
# wsl.exe:
#   (a) check that WSL is here (it never elevates; without WSL it names the admin command);
#   (b) pick a distro: an existing one, or install Arch or Ubuntu with --no-launch;
#   (c) stage 1 as root, in this terminal, with UM_DRIVER=ps1;
#   (d) on exit code 10, terminate the distro so wsl.conf (systemd, default user) applies;
#   (e) stage 2 as the new default user: umbra bootstrap resume.
# It never changes the execution policy, and never calls exit (under iex that would close the
# window): it returns, and leaves the result in $LASTEXITCODE.
#
# Environment (all optional; tests and the real gate use them):
#   UM_PS1_DISTRO       online name to install (archlinux, Ubuntu-24.04) or an existing distro
#   UM_PS1_DISTRO_NAME  the name of a new distro (default: the online name)
#   UM_PS1_URL          install.sh to run in stage 1 (default: the bootstrapper's main branch)
#   UM_PS1_STAGE1       a bash command run as stage 1 instead of install.sh (the G-A2 gate)
#   UM_PS1_NO_RUN=1     define the functions only (Pester dot-sources this file)
# This file stays ASCII: Windows PowerShell 5.1 reads a BOM-less file as ANSI.

$UmRestartCode = 10
$UmInstallSh = 'https://raw.githubusercontent.com/Robertcl795/umbra-bootstrapper/main/install.sh'
$UmOnline = @(
  @{ Name = 'archlinux'; Label = 'Arch Linux' },
  @{ Name = 'Ubuntu-24.04'; Label = 'Ubuntu 24.04 LTS' }
)

# Invoke-UmWsl: the only place wsl.exe runs (Pester mocks it); the exit code is $LASTEXITCODE.
# Called as a statement, never assigned: assigning would capture stdout, and umbra-setup needs
# the console (verify at G-A2 through irm | iex). With -Capture it returns the output lines
# (WSL_UTF8=1, and NULs stripped for an older WSL that writes UTF-16).
function Invoke-UmWsl {
  param([string[]]$Arguments, [switch]$Capture)
  $env:WSL_UTF8 = '1'
  if ($Capture) {
    $out = & wsl.exe @Arguments 2>$null
    return @($out | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
  }
  & wsl.exe @Arguments
}

function Write-UmStep([string]$Text) { Write-Host "umbra: $Text" }

# (a) WSL is here when wsl.exe answers --version (an inbox stub without WSL does not).
function Test-UmWsl {
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
  $null = Invoke-UmWsl @('--version') -Capture
  return ($LASTEXITCODE -eq 0)
}

function Get-UmDistros { return @(Invoke-UmWsl @('--list', '--quiet') -Capture) }

# (b) The choice: UM_PS1_DISTRO, else a menu of the existing distros and the online ones.
# Returns @{ Name; Online } (Online is $null for an existing distro), or $null when cancelled.
function Select-UmDistro([string[]]$Existing) {
  $want = $env:UM_PS1_DISTRO
  if ($want) {
    if ($Existing -contains $want) { return @{ Name = $want; Online = $null } }
    $name = if ($env:UM_PS1_DISTRO_NAME) { $env:UM_PS1_DISTRO_NAME } else { $want }
    if ($Existing -contains $name) { return @{ Name = $name; Online = $null } }
    return @{ Name = $name; Online = $want }
  }
  $choices = @()
  foreach ($d in $Existing) { $choices += @{ Name = $d; Online = $null; Label = "$d (installed)" } }
  foreach ($o in $UmOnline) {
    if ($Existing -notcontains $o.Name) { $choices += @{ Name = $o.Name; Online = $o.Name; Label = "$($o.Label) (new)" } }
  }
  Write-Host 'Which distro gets Umbra?'
  for ($i = 0; $i -lt $choices.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $choices[$i].Label) }
  $answer = Read-Host 'Number (empty to cancel)'
  $n = 0
  if (-not [int]::TryParse($answer, [ref]$n) -or $n -lt 1 -or $n -gt $choices.Count) { return $null }
  return $choices[$n - 1]
}

# (c) The stage 1 command: install.sh fetched to a file (it reads the terminal), driver mode on.
# No double quotes: Windows PowerShell 5.1 drops them from a native command's arguments. A
# mktemp path has no spaces. UM_PS1_STAGE1 replaces the fetch with a command of its own (the
# G-A2 gate runs a local build: install.sh only runs the pinned release).
function Get-UmStage1Command([string]$Url) {
  if ($env:UM_PS1_STAGE1) { return "export UM_DRIVER=ps1; $($env:UM_PS1_STAGE1)" }
  return "f=`$(mktemp) && curl -fsSL '$Url' -o `$f && UM_DRIVER=ps1 bash `$f; rc=`$?; rm -f `$f; exit `$rc"
}

function Install-Umbra {
  $global:LASTEXITCODE = 0
  if (-not (Test-UmWsl)) {
    Write-UmStep 'WSL is not installed. In an administrator PowerShell, run:'
    Write-Host '  wsl --install --no-distribution'
    Write-UmStep 'Then restart Windows and run this command again.'
    $global:LASTEXITCODE = 1
    return
  }
  $pick = Select-UmDistro (Get-UmDistros)
  if (-not $pick) { Write-UmStep 'cancelled.'; $global:LASTEXITCODE = 130; return }
  $name = $pick.Name
  if ($pick.Online) {
    Write-UmStep "installing $($pick.Online) as $name"
    Invoke-UmWsl @('--install', $pick.Online, '--no-launch', '--name', $name); $rc = $LASTEXITCODE
    if ($rc -ne 0) { Write-UmStep "wsl --install failed ($rc)."; $global:LASTEXITCODE = $rc; return }
  }
  $url = if ($env:UM_PS1_URL) { $env:UM_PS1_URL } else { $UmInstallSh }
  Write-UmStep "stage 1 in $name"
  Invoke-UmWsl @('-d', $name, '-u', 'root', '--exec', 'bash', '-lc', (Get-UmStage1Command $url)); $rc = $LASTEXITCODE
  if ($rc -eq 0) {
    Write-UmStep "stage 1 is done. To finish later: wsl.exe --terminate $name, then wsl.exe -d $name and umbra bootstrap resume"
    return
  }
  if ($rc -ne $UmRestartCode) { Write-UmStep "stage 1 stopped ($rc)."; $global:LASTEXITCODE = $rc; return }
  Write-UmStep "restarting $name so your user and systemd take effect"
  Invoke-UmWsl @('--terminate', $name); $rc = $LASTEXITCODE
  if ($rc -ne 0) { Write-UmStep "wsl --terminate failed ($rc)."; $global:LASTEXITCODE = $rc; return }
  Write-UmStep "stage 2 in $name"
  Invoke-UmWsl @('-d', $name, '--cd', '~', '--exec', 'bash', '-lc', 'umbra bootstrap resume'); $rc = $LASTEXITCODE
  $global:LASTEXITCODE = $rc
  if ($rc -eq 0) { Write-UmStep "done. Open it any time with: wsl.exe -d $name" }
  else { Write-UmStep "stage 2 stopped ($rc). Run again inside the distro: umbra bootstrap resume" }
}

if ($env:UM_PS1_NO_RUN -ne '1') { Install-Umbra }
