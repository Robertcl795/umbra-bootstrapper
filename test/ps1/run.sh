#!/usr/bin/env bash
# run.sh: the Pester tests of install.ps1, through Windows PowerShell 5.1 from WSL (ADR 0042).
# -ExecutionPolicy Bypass applies to this one process only; the machine's policy is untouched.
# Prints "skip" and exits 0 where powershell.exe is not reachable (CI on Linux).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
command -v powershell.exe >/dev/null 2>&1 || { echo "skip: no powershell.exe"; exit 0; }
win=$(wslpath -w "$here/install.Tests.ps1")
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
  "Import-Module Pester -MaximumVersion 4.99; \$r = Invoke-Pester -Script '$win' -PassThru; if (\$r.FailedCount -gt 0) { exit 1 }" | tr -d '\r'
