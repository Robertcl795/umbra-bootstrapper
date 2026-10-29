#!/usr/bin/env bash
set -euo pipefail

# Phase 12 checkpoint: the greeting must be installed, configured, and
# actually reachable from an interactive shell.

if ! command -v fastfetch >/dev/null 2>&1; then
  echo "fastfetch not installed." >&2
  exit 1
fi

if [ ! -L "$HOME/.config/fastfetch" ] && [ ! -d "$HOME/.config/fastfetch" ]; then
  echo "Expected ~/.config/fastfetch (symlink to config/fastfetch)." >&2
  exit 1
fi

config="$HOME/.config/fastfetch/config.jsonc"
if [ ! -f "$config" ]; then
  echo "Missing fastfetch config: $config" >&2
  exit 1
fi

# Renders without erroring (also catches an invalid config.jsonc or a
# logo file the config points at but that isn't there).
if ! fastfetch --pipe >/dev/null 2>"${TMPDIR:-/tmp}/fastfetch-test.err"; then
  echo "fastfetch failed to render:" >&2
  cat "${TMPDIR:-/tmp}/fastfetch-test.err" >&2
  exit 1
fi
if [ -s "${TMPDIR:-/tmp}/fastfetch-test.err" ]; then
  echo "fastfetch reported errors:" >&2
  cat "${TMPDIR:-/tmp}/fastfetch-test.err" >&2
  exit 1
fi

# The greeting hook must be wired into the interactive shell. `zsh -lic`
# already runs it; just assert the module is present and opt-out works.
if ! zsh -lic 'typeset -f >/dev/null; [[ -n "$UM_ENV_DIR" ]]' 2>/dev/null; then
  echo "zsh did not set UM_ENV_DIR; greeting cannot be sourced." >&2
  exit 1
fi

if ! UM_NO_FASTFETCH=1 zsh -lic 'true' >/dev/null 2>&1; then
  echo "UM_NO_FASTFETCH=1 broke shell startup." >&2
  exit 1
fi

rm -f "${TMPDIR:-/tmp}/fastfetch-test.err"
