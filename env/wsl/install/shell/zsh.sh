#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

ZSH_PLUGINS=(
  "zsh-users/zsh-autosuggestions"
  "zsh-users/zsh-history-substring-search"
  "jeffreytse/zsh-vi-mode"
  "zdharma-continuum/fast-syntax-highlighting"
)

install_zsh() {
  log_step "Phase 3: Shell setup (zsh)"

  if ! ensure_cmd zsh; then
    case "${UM_OS:-}" in
      ubuntu) sudo apt-get install -y zsh ;;
      arch|omarchy) sudo pacman -S --noconfirm --needed zsh ;;
      *) die "Unknown OS for zsh install" ;;
    esac
  fi

  # Pre-clone the plugins config/zsh/plugins.zsh loads, so the first shell
  # launch is instant and works offline.
  local plugin_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
  mkdir -p "$plugin_dir"
  local repo name
  for repo in "${ZSH_PLUGINS[@]}"; do
    name="${repo##*/}"
    if [ ! -d "$plugin_dir/$name" ]; then
      log_info "Cloning zsh plugin: $repo"
      git clone --depth=1 "https://github.com/$repo" "$plugin_dir/$name" \
        || log_warn "Could not pre-clone $repo (it will be retried on first shell launch)."
    fi
  done

  # State/cache dirs used by history and completion
  mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/zsh" "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"

  # ADR 0011: on Omarchy the login shell stays Omarchy's.
  if [ "$UM_SHELL" = "zsh" ] && [ "${UM_OS:-}" != "omarchy" ]; then
    set_default_shell_zsh
  fi
}

set_default_shell_zsh() {
  local zsh_path current_shell
  zsh_path="$(command -v zsh)"
  current_shell="$(getent passwd "$USER" | cut -d: -f7 || true)"

  if [ "$current_shell" = "$zsh_path" ]; then
    log_info "zsh is already the default shell."
    return 0
  fi

  if [ "$UM_NONINTERACTIVE" != "1" ] && ! confirm "Set zsh as default shell?" "y"; then
    return 0
  fi

  # chsh refuses shells missing from /etc/shells
  if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
  fi

  # usermod via sudo avoids chsh's password prompt (which silently fails
  # in scripted runs); fall back to chsh for systems without usermod.
  log_info "Setting zsh as default shell for $USER..."
  if sudo usermod -s "$zsh_path" "$USER" 2>/dev/null || chsh -s "$zsh_path"; then
    log_info "Default shell changed to zsh (takes effect on next login)."
  else
    log_warn "Unable to change default shell. Run manually: chsh -s $zsh_path"
  fi
}

if [ "${1:-}" = "--run" ]; then
  install_zsh
fi
