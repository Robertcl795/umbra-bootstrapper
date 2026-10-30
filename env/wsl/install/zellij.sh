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
      arch) run_priv pacman -S --noconfirm --needed zellij ;;
      ubuntu)
        local rust_arch
        case "$(detect_arch)" in
          arm64) rust_arch="aarch64" ;;
          *) rust_arch="x86_64" ;;
        esac
        # pin-downloads (ADR 0006): pinned version, sha256 from install/checksums.sha256.
        local url="https://github.com/zellij-org/zellij/releases/download/v${UM_ZELLIJ_VERSION:-0.45.1}/zellij-${rust_arch}-unknown-linux-musl.tar.gz"
        install_release_bin zellij "$url" "$(pinned_sha256 "$url")"
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

  # chezmoi-unlink (ADR 0006): ~/.config/zellij/config.kdl is deployed by chezmoi.
  log_info "Zellij installed (config: ~/.config/zellij/config.kdl, managed by chezmoi)."
}

if [ "${1:-}" = "--run" ]; then
  install_zellij
fi
