#!/usr/bin/env bash
set -euo pipefail

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require git
require curl
require wget
require unzip
require rg
require fzf
require zoxide
require nvim
require starship

# Core CLI stack (Phase 1)
require lazygit
require glow
require duf
require lazydocker
require yazi
require sshs
require lnav
require just
require zellij

if ! command -v fd >/dev/null 2>&1 && ! command -v fdfind >/dev/null 2>&1; then
  echo "Missing fd or fdfind." >&2
  exit 1
fi

if ! command -v bat >/dev/null 2>&1 && ! command -v batcat >/dev/null 2>&1; then
  echo "Missing bat or batcat." >&2
  exit 1
fi

if ! command -v eza >/dev/null 2>&1 && ! command -v exa >/dev/null 2>&1; then
  echo "Missing eza or exa." >&2
  exit 1
fi

if ! command -v tldr >/dev/null 2>&1 && ! command -v tealdeer >/dev/null 2>&1; then
  echo "Missing tldr or tealdeer." >&2
  exit 1
fi
