#!/usr/bin/env bash
set -euo pipefail

export STARSHIP_CONFIG="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
export STARSHIP_SHELL="sh"
export STARSHIP_SESSION_KEY="1"

starship prompt >/dev/null
