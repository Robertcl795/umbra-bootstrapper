#!/usr/bin/env bash
# 15_pwsh7.sh — PowerShell 7 is installed for this Windows user (component pwsh7).
set -euo pipefail
TESTS_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UM_ENV_DIR="${UM_ENV_DIR:-$(cd -- "$TESTS_DIR/.." && pwd)}"
# shellcheck disable=SC1091
source "$UM_ENV_DIR/install/terminal.sh"
p="$(pwsh_exe)"
if [ -z "$p" ]; then
  echo "pwsh.exe not found (PowerShell 7 is not installed)." >&2
  exit 1
fi
v="$(pwsh_version "$p")"
if ! [ "${v%%.*}" -ge 7 ] 2>/dev/null; then
  echo "pwsh.exe is version '${v:-unknown}', want 7 or later." >&2
  exit 1
fi
