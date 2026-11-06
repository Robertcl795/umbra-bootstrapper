#!/usr/bin/env bash
# The Windows Terminal fragment (ADR 0043): it exists and its profile names one of its schemes.
# Without interop (the Windows side out of reach) it warns and passes.
set -euo pipefail
la_w="${UM_WIN_LOCALAPPDATA_W:-}"
if [ -z "$la_w" ]; then
  la_w="$(cd /mnt/c 2>/dev/null; cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')" || la_w=""
fi
la_u="${UM_WIN_LOCALAPPDATA_U:-$( [ -z "$la_w" ] || wslpath -u "$la_w" 2>/dev/null || true)}"
if [ -z "$la_u" ] || [ ! -d "$la_u" ]; then
  echo "[warn] The Windows side is not reachable; the Windows Terminal fragment is not checked." >&2
  exit 0
fi
f="$la_u/Microsoft/Windows Terminal/Fragments/Umbra/umbra.json"
[ -s "$f" ] || { echo "Windows Terminal fragment missing: $f (run: bash \$UM_ENV_DIR/install/terminal.sh --run)" >&2; exit 1; }
scheme="$(grep -o '"colorScheme": "[^"]*"' "$f" | head -n 1 | cut -d'"' -f4)"
grep -q "\"name\": \"$scheme\"" "$f" || { echo "The fragment's profile names a scheme it does not define: '$scheme'." >&2; exit 1; }
