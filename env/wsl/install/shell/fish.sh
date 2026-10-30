#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

install_fish() {
  log_step "Phase 3: Shell setup (fish)"

  if ! ensure_cmd fish; then
    case "${UM_OS:-}" in
      ubuntu) run_priv apt-get install -y fish ;;
      arch) run_priv pacman -S --noconfirm --needed fish ;;
      *) die "Unknown OS for fish install" ;;
    esac
  fi

  if [ ! -d "$HOME/.config/fish" ]; then
    mkdir -p "$HOME/.config/fish"
  fi

  if [ ! -f "$HOME/.config/fish/functions/fisher.fish" ]; then
    log_info "Installing fisher plugin manager."
    curl -fsSL https://git.io/fisher | fish -c 'source; and fisher install jorgebucaran/fisher'
  fi

  fish -c "fisher install PatrickF1/fzf.fish" >/dev/null 2>&1 || true

  if [ "$UM_SHELL" = "fish" ] && ensure_cmd chsh; then
    if [ "$UM_NONINTERACTIVE" = "1" ]; then
      log_warn "Skipping default shell change in non-interactive mode."
    else
      if confirm "Set fish as default shell?" "n"; then
        chsh -s "$(command -v fish)" || log_warn "Unable to change default shell."
      fi
    fi
  fi
}

if [ "${1:-}" = "--run" ]; then
  install_fish
fi
