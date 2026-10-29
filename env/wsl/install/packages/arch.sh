#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

install_packages_arch() {
  log_step "Phase 1: System update + base packages (Arch)"

  if [ ! -d /etc/pacman.d/gnupg ] || ! sudo pacman-key --list-keys >/dev/null 2>&1; then
    log_info "Initializing pacman keyring..."
    sudo pacman-key --init
    sudo pacman-key --populate archlinux
  fi

  sudo pacman -Sy --noconfirm

  sudo pacman -S --noconfirm --needed \
    base-devel git curl wget unzip ca-certificates \
    ripgrep fd bat eza fzf zoxide neovim starship \
    tldr zsh \
    lazygit glow duf lazydocker yazi lnav just zellij fastfetch

  # ADR 0004: fish only when it is the chosen shell.
  if [ "${UM_SHELL:-zsh}" = "fish" ]; then
    sudo pacman -S --noconfirm --needed fish
  fi

  install_sshs_arch

  log_info "Base packages installed."
}

# Bootstrap yay (AUR helper) from the yay-bin PKGBUILD if missing.
ensure_yay() {
  if ensure_cmd yay; then
    return 0
  fi
  log_info "Installing yay (AUR helper)..."
  local tmp
  tmp="$(mktemp -d)"
  if git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" \
    && (cd "$tmp/yay-bin" && makepkg -si --noconfirm); then
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp"
  log_warn "Could not bootstrap yay."
  return 1
}

# sshs is not in the official repos: try AUR, then cargo, then release binary.
install_sshs_arch() {
  if ensure_cmd sshs; then
    return 0
  fi
  if ensure_yay && yay -S --noconfirm --needed sshs; then
    return 0
  fi
  if ensure_cmd cargo && cargo install sshs; then
    return 0
  fi
  local arch
  arch="$(detect_arch)"
  install_release_bin sshs "https://github.com/quantumsheep/sshs/releases/latest/download/sshs-linux-${arch}" \
    || log_warn "sshs could not be installed (AUR/cargo/release all failed)."
}

if [ "${1:-}" = "--run" ]; then
  install_packages_arch
fi
