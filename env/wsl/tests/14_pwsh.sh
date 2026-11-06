#!/usr/bin/env bash
# The PowerShell prompt (ADR 0043): Umbra's starship.toml exists. The $PROFILE block is the user's
# file; it is not checked here, and the execution policy is only reported by terminal.sh --pwsh.
set -euo pipefail
la_w="${UM_WIN_LOCALAPPDATA_W:-$(cd /mnt/c 2>/dev/null && cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r' || true)}"
la_u="${UM_WIN_LOCALAPPDATA_U:-$( [ -z "$la_w" ] || wslpath -u "$la_w" 2>/dev/null || true)}"
if [ -z "$la_u" ] || [ ! -d "$la_u" ]; then
  echo "[warn] The Windows side is not reachable; the PowerShell prompt is not checked." >&2
  exit 0
fi
[ -s "$la_u/umbra/starship.toml" ] || { echo "Umbra's starship.toml for PowerShell is missing (run: bash \$UM_ENV_DIR/install/terminal.sh --pwsh)" >&2; exit 1; }
