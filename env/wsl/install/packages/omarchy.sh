#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# ADR 0011: on Omarchy, Umbra only adds the tools Omarchy lacks. `pacman -S --needed` leaves
# installed packages alone; never `pacman -Sy`/`-Syu` (system updates belong to Omarchy's menu).
# Omarchy's editor, terminal, fonts and mise are not in this list.
install_packages_omarchy() {
  log_step "Phase 1: Extra tools (Omarchy, pacman -S --needed only)"

  if ! sudo pacman -S --noconfirm --needed \
    git curl zsh ripgrep fd bat eza fzf zoxide starship \
    tldr glow duf lnav just zellij; then
    die "pacman could not install the extra tools. Update Omarchy from its menu (Update > Omarchy), then run Umbra again."
  fi

  log_info "Extra tools installed."
}

if [ "${1:-}" = "--run" ]; then
  install_packages_omarchy
fi
