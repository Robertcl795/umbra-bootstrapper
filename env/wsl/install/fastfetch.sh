#!/usr/bin/env bash
set -euo pipefail

# Phase 12: fastfetch — the greeting printed by every new interactive shell
# (config/zsh/greeting.zsh, shells/fish/conf.d/greeting.fish).
#
# The config itself is symlinked by install/link.sh; this phase only makes
# sure the binary exists and shows what the greeting will look like.

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

install_fastfetch() {
  log_step "Phase 12: Shell greeting (fastfetch)"

  if ! ensure_cmd fastfetch; then
    case "${UM_OS:-}" in
      arch)
        sudo pacman -S --noconfirm --needed fastfetch \
          || log_warn "pacman could not install fastfetch."
        ;;
      ubuntu)
        # In the archive from 24.10 onwards; older releases fall through to
        # the upstream release tarball below.
        sudo apt-get install -y fastfetch 2>/dev/null \
          || log_info "fastfetch is not in apt for this release; using the upstream build."
        ;;
    esac
  fi

  if ! ensure_cmd fastfetch; then
    local arch
    arch="$(detect_arch)"
    install_release_bin fastfetch \
      "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${arch}.tar.gz" \
      || log_warn "fastfetch could not be installed; shells will start without a greeting."
  fi

  if ! ensure_cmd fastfetch; then
    return 0
  fi

  # ~/.config/fastfetch is symlinked in phase 2; if this phase runs on its
  # own (make fastfetch) the link may not exist yet.
  symlink_with_backup "$UM_ENV_DIR/config/fastfetch" "$HOME/.config/fastfetch"

  log_info "fastfetch installed. Every new interactive shell now opens with:"
  echo "" >&2
  fastfetch >&2 || log_warn "fastfetch ran with errors; check ~/.config/fastfetch/config.jsonc"
  echo "" >&2
  log_info "Turn the greeting off with: export UM_NO_FASTFETCH=1 (in ~/.zshrc.local)"
}

if [ "${1:-}" = "--run" ]; then
  install_fastfetch
fi
