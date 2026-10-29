#!/usr/bin/env bash
set -euo pipefail

# WSL optimizations (Phase 4). Skipped entirely outside WSL.

# UM_IS_WSL=1|0 overrides the detection (used by container tests).
if [ "${UM_IS_WSL:-}" = "0" ] || { [ "${UM_IS_WSL:-}" != "1" ] && ! grep -qi microsoft /proc/version 2>/dev/null; }; then
  echo "Not WSL; skipping WSL checks." >&2
  exit 0
fi

if [ ! -f /etc/wsl.conf ]; then
  echo "/etc/wsl.conf missing." >&2
  exit 1
fi
grep -q "systemd=true" /etc/wsl.conf || { echo "systemd not enabled in /etc/wsl.conf." >&2; exit 1; }

# .wslconfig on the Windows host (best-effort: interop may be unavailable)
profile=""
if command -v wslvar >/dev/null 2>&1; then
  profile="$(wslvar USERPROFILE 2>/dev/null || true)"
fi
if [ -z "$profile" ] && [ -x /mnt/c/Windows/System32/cmd.exe ]; then
  profile="$(cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || true)"
fi

if [ -n "$profile" ]; then
  wslconfig="$(wslpath -u "$profile" 2>/dev/null)/.wslconfig"
  if [ -f "$wslconfig" ]; then
    for key in networkingMode dnsTunneling autoProxy; do
      grep -qi "$key" "$wslconfig" || echo "[warn] $key not set in .wslconfig" >&2
    done
  else
    echo "[warn] .wslconfig not found at $wslconfig" >&2
  fi
else
  echo "[warn] Could not resolve Windows user profile (interop disabled?)." >&2
fi

# The repo itself should not live on NTFS
case "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" in
  /mnt/*) echo "[warn] the umbra checkout lives under /mnt (NTFS) — expect slow I/O." >&2 ;;
esac

echo "WSL checks OK."
