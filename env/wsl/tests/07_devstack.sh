#!/usr/bin/env bash
set -euo pipefail

# Dev stack (Phase 3): rustup / fnm / uv / AI CLIs must be reachable
# without restarting the WSL session.

# shellcheck disable=SC1091
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
# idempotency-fix: current pnpm installers (v12 seen in tests) put the binary in $PNPM_HOME/bin.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.opencode/bin:$PNPM_HOME/bin:$PNPM_HOME:$PATH"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require rustup
require cargo
require fnm
require pnpm
require uv
require claude
# opencode is personal-only (ADR 0007, decision 11).
if [ "${UM_MODE:-personal}" != "work" ]; then
  require opencode
fi
require gh

rustup show >/dev/null
uv --version >/dev/null
fnm --version >/dev/null
pnpm --version >/dev/null

# fnm must have a default so new shells get node without 'fnm use'
if ! fnm ls 2>/dev/null | grep -q default; then
  echo "No default Node version set in fnm (run 'fnm default lts-latest')." >&2
  exit 1
fi

if ! gh extension list 2>/dev/null | grep -q gh-copilot; then
  echo "[warn] gh-copilot extension not installed (requires 'gh auth login')." >&2
fi

echo "Dev stack OK."
