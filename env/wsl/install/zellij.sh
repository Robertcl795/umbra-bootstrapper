#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

install_zellij() {
  log_step "Phase 7: Zellij multiplexer"

  if ! ensure_cmd zellij; then
    case "${UM_OS:-}" in
      arch) sudo pacman -S --noconfirm --needed zellij ;;
      ubuntu)
        local rust_arch
        case "$(detect_arch)" in
          arm64) rust_arch="aarch64" ;;
          *) rust_arch="x86_64" ;;
        esac
        install_release_bin zellij "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${rust_arch}-unknown-linux-musl.tar.gz"
        ;;
      *)
        if ensure_cmd cargo; then
          cargo install zellij
        else
          die "Unknown OS for zellij install"
        fi
        ;;
    esac
  fi

  symlink_with_backup "$UM_ENV_DIR/config/zellij/config.kdl" "$HOME/.config/zellij/config.kdl"
  log_info "Zellij configured (config: ~/.config/zellij/config.kdl)."
}

if [ "${1:-}" = "--run" ]; then
  install_zellij
fi
