#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

install_packages_ubuntu() {
  log_step "Phase 1: System update + base packages (Ubuntu)"
  sudo apt-get update
  sudo apt-get install -y \
    build-essential git curl wget unzip ca-certificates \
    ripgrep fd-find bat \
    fzf zoxide neovim zsh
  # ADR 0004: fish only when it is the chosen shell.
  if [ "${UM_SHELL:-zsh}" = "fish" ]; then
    sudo apt-get install -y fish
  fi

  if ! sudo apt-get install -y eza; then
    log_warn "eza has no installable candidate; trying exa instead."
    sudo apt-get install -y exa || log_warn "Neither eza nor exa is installable via apt; skipping."
  fi

  # `apt-cache show tldr` can return 0 (cached metadata) even when apt has no
  # installable candidate for the current release/arch, which made the old
  # candidate-check give a false positive and take down the whole bootstrap
  # under `set -e` when `apt-get install` then failed. Just attempt the
  # install directly (inside an `if`, so failure never trips errexit) and
  # fall back to tealdeer; skip entirely if neither is installable.
  if ! sudo apt-get install -y tldr; then
    log_warn "tldr has no installable candidate; trying tealdeer instead."
    if ! sudo apt-get install -y tealdeer; then
      log_warn "Neither tldr nor tealdeer is installable via apt; skipping (cheat-sheet lookups won't be available)."
    fi
  fi

  if ! ensure_cmd starship; then
    log_info "Installing Starship via official installer."
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y
  fi

  if ensure_cmd fdfind && ! ensure_cmd fd; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi

  if ensure_cmd batcat && ! ensure_cmd bat; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi

  if ensure_cmd exa && ! ensure_cmd eza; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v exa)" "$HOME/.local/bin/eza"
  fi

  install_cli_extras_ubuntu

  log_info "Base packages installed."
}

# Core CLI extras. Ubuntu's apt archive lags behind Arch, so tools missing
# from apt come from GitHub release binaries (versions overridable via env).
install_cli_extras_ubuntu() {
  log_step "Core CLI extras (lazygit, glow, duf, lazydocker, yazi, sshs, lnav, just, zellij)"

  sudo apt-get install -y duf just lnav || log_warn "apt could not install duf/just/lnav; continuing."

  local arch rust_arch
  arch="$(detect_arch)"
  case "$arch" in
    arm64) rust_arch="aarch64" ;;
    *) rust_arch="x86_64" ;;
  esac

  local lazygit_ver="${UM_LAZYGIT_VERSION:-0.44.1}"
  local glow_ver="${UM_GLOW_VERSION:-2.1.0}"
  local lazydocker_ver="${UM_LAZYDOCKER_VERSION:-0.24.1}"
  local goarch_suffix
  case "$arch" in
    arm64) goarch_suffix="Linux_arm64" ;;
    *) goarch_suffix="Linux_x86_64" ;;
  esac

  install_release_bin lazygit "https://github.com/jesseduffield/lazygit/releases/download/v${lazygit_ver}/lazygit_${lazygit_ver}_${goarch_suffix}.tar.gz"
  install_release_bin glow "https://github.com/charmbracelet/glow/releases/download/v${glow_ver}/glow_${glow_ver}_${goarch_suffix}.tar.gz"
  install_release_bin lazydocker "https://github.com/jesseduffield/lazydocker/releases/download/v${lazydocker_ver}/lazydocker_${lazydocker_ver}_${goarch_suffix}.tar.gz"
  install_release_bin zellij "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${rust_arch}-unknown-linux-musl.tar.gz"
  install_release_bin yazi "https://github.com/sxyazi/yazi/releases/latest/download/yazi-${rust_arch}-unknown-linux-gnu.zip"
  install_release_bin sshs "https://github.com/quantumsheep/sshs/releases/latest/download/sshs-linux-${arch}"

  # fastfetch entered the Ubuntu archive in 24.10; older releases (and the
  # LTS) need the upstream build.
  if ! ensure_cmd fastfetch && ! sudo apt-get install -y fastfetch 2>/dev/null; then
    install_release_bin fastfetch "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${arch}.tar.gz"
  fi

  if ! ensure_cmd duf; then
    local duf_ver="${UM_DUF_VERSION:-0.8.1}"
    install_release_bin duf "https://github.com/muesli/duf/releases/download/v${duf_ver}/duf_${duf_ver}_linux_${arch}.tar.gz"
  fi
}

if [ "${1:-}" = "--run" ]; then
  install_packages_ubuntu
fi
