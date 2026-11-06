# Pester 3.4 tests for install.ps1 (ADR 0042). wsl.exe is never run: Invoke-UmWsl is mocked,
# records each call and answers with the exit code the case sets. Run: test/ps1/run.sh
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:UM_PS1_NO_RUN = '1'
. (Join-Path $here '..\..\install.ps1')

# Fake: $script:Codes maps the first argument (or '-d root' / '-d user') to an exit code;
# $script:Calls collects every call as one joined line.
function Use-FakeWsl([hashtable]$Codes, [string[]]$Distros = @()) {
  $script:Calls = New-Object System.Collections.ArrayList
  $script:Codes = $Codes
  $script:Distros = $Distros
  Mock Get-Command { $true } -ParameterFilter { $Name -eq 'wsl.exe' }
  Mock Write-Host {}
  Mock Invoke-UmWsl {
    [void]$script:Calls.Add(($Arguments -join ' '))
    $key = $Arguments[0]
    if ($key -eq '-d') { $key = if ($Arguments -contains 'root') { 'stage1' } else { 'stage2' } }
    $global:LASTEXITCODE = if ($script:Codes.ContainsKey($key)) { $script:Codes[$key] } else { 0 }
    if ($Capture -and $key -eq '--list') { return $script:Distros }
    if ($Capture) { return @() }
  }
}

Describe 'install.ps1' {
  BeforeEach {
    $env:UM_PS1_DISTRO = 'archlinux'; $env:UM_PS1_DISTRO_NAME = 'umbra-test'; $env:UM_PS1_URL = 'https://example.invalid/install.sh'
  }
  AfterEach {
    Remove-Item Env:UM_PS1_DISTRO, Env:UM_PS1_DISTRO_NAME, Env:UM_PS1_URL -ErrorAction SilentlyContinue
  }

  It 'installs, runs stage 1, restarts on code 10 and runs stage 2, in that order' {
    Use-FakeWsl @{ stage1 = 10 }
    Install-Umbra
    $LASTEXITCODE | Should Be 0
    $script:Calls.Count | Should Be 6
    $script:Calls[0] | Should Be '--version'
    $script:Calls[1] | Should Be '--list --quiet'
    $script:Calls[2] | Should Be '--install archlinux --no-launch --name umbra-test'
    $script:Calls[3] | Should Match '^-d umbra-test -u root --exec bash -lc '
    $script:Calls[3] | Should Match "curl -fsSL 'https://example.invalid/install.sh'"
    $script:Calls[3] | Should Match 'UM_DRIVER=ps1 bash'
    $script:Calls[4] | Should Be '--terminate umbra-test'
    $script:Calls[5] | Should Be '-d umbra-test --cd ~ --exec bash -lc umbra bootstrap resume'
  }

  It 'passes no double quote to wsl.exe (Windows PowerShell 5.1 drops them from native arguments)' {
    Use-FakeWsl @{ stage1 = 10 }
    Install-Umbra
    ($script:Calls | Where-Object { $_ -match '"' }) | Should BeNullOrEmpty
  }

  It 'UM_PS1_STAGE1 replaces the install.sh fetch; UM_DRIVER=ps1 is still exported first' {
    $env:UM_PS1_STAGE1 = '/opt/gate/stage1 --env-dir /opt/gate/env'
    try {
      Use-FakeWsl @{ stage1 = 10 }
      Install-Umbra
      $script:Calls[3] | Should Be '-d umbra-test -u root --exec bash -lc export UM_DRIVER=ps1; /opt/gate/stage1 --env-dir /opt/gate/env'
    } finally { Remove-Item Env:UM_PS1_STAGE1 }
  }

  It 'reuses an existing distro without installing it' {
    Use-FakeWsl @{ stage1 = 10 } @('umbra-test')
    Install-Umbra
    ($script:Calls | Where-Object { $_ -like '--install*' }) | Should BeNullOrEmpty
    $script:Calls[2] | Should Match '^-d umbra-test -u root'
  }

  It 'stops after stage 1 when it exits 0 (q on the restart screen): no terminate, no stage 2' {
    Use-FakeWsl @{ stage1 = 0 }
    Install-Umbra
    $LASTEXITCODE | Should Be 0
    ($script:Calls | Where-Object { $_ -like '--terminate*' }) | Should BeNullOrEmpty
    $script:Calls[-1] | Should Match '-u root'
  }

  It 'passes a stage 1 failure through and runs nothing after it' {
    Use-FakeWsl @{ stage1 = 1 }
    Install-Umbra
    $LASTEXITCODE | Should Be 1
    $script:Calls[-1] | Should Match '-u root'
  }

  It 'stops when wsl --install fails' {
    Use-FakeWsl @{ '--install' = 5 }
    Install-Umbra
    $LASTEXITCODE | Should Be 5
    $script:Calls[-1] | Should Match '^--install'
  }

  It 'passes a stage 2 failure through' {
    Use-FakeWsl @{ stage1 = 10; stage2 = 1 }
    Install-Umbra
    $LASTEXITCODE | Should Be 1
  }

  It 'without WSL names the admin command and runs nothing else' {
    Use-FakeWsl @{ '--version' = 1 }
    Install-Umbra
    $LASTEXITCODE | Should Be 1
    $script:Calls.Count | Should Be 1
    Assert-MockCalled Write-Host -ParameterFilter { $Object -eq '  wsl --install --no-distribution' } -Exactly 1
  }

  It 'never changes the execution policy and never calls exit' {
    $src = Get-Content (Join-Path $here '..\..\install.ps1') | Where-Object { $_ -notmatch '^\s*#' }
    ($src | Select-String 'Set-ExecutionPolicy') | Should BeNullOrEmpty
    ($src | Select-String '\bexit\b' | Where-Object { $_.Line -notmatch 'exit `\$rc' }) | Should BeNullOrEmpty
  }

  It 'menu: lists installed distros first, then the online ones not installed; empty cancels' {
    Remove-Item Env:UM_PS1_DISTRO
    Mock Write-Host {}
    Mock Read-Host { '2' }
    $pick = Select-UmDistro @('Ubuntu-24.04')
    $pick.Name | Should Be 'archlinux'
    $pick.Online | Should Be 'archlinux'
    Mock Read-Host { '1' }
    (Select-UmDistro @('Ubuntu-24.04')).Online | Should BeNullOrEmpty
    Mock Read-Host { '' }
    Select-UmDistro @() | Should BeNullOrEmpty
  }
}
