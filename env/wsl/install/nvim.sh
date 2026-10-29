#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

install_nvim() {
  log_step "Phase 5: Neovim"

  if ! ensure_cmd nvim; then
    case "${UM_OS:-}" in
      ubuntu) sudo apt-get install -y neovim ;;
      arch) sudo pacman -S --noconfirm --needed neovim ;;
      *) die "Unknown OS for neovim install" ;;
    esac
  fi

  # chezmoi-unlink (ADR 0006): ~/.config/nvim is deployed by chezmoi.
  log_info "Neovim installed (config: ~/.config/nvim, managed by chezmoi)."
}

if [ "${1:-}" = "--run" ]; then
  install_nvim
fi
