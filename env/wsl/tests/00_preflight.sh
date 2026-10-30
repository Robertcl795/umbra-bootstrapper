#!/usr/bin/env bash
set -euo pipefail

# UM_IS_WSL=1|0 overrides the detection (used by container tests).
if [ "${UM_IS_WSL:-}" = "0" ] || { [ "${UM_IS_WSL:-}" != "1" ] && ! grep -qi microsoft /proc/version 2>/dev/null; }; then
  echo "Not running under WSL." >&2
  exit 1
fi

if [ ! -f /etc/os-release ]; then
  echo "/etc/os-release not found." >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required." >&2
  exit 1
fi

if command -v curl >/dev/null 2>&1; then
  curl -fsSL https://example.com >/dev/null
elif command -v wget >/dev/null 2>&1; then
  wget -qO- https://example.com >/dev/null
else
  echo "curl or wget required." >&2
  exit 1
fi
