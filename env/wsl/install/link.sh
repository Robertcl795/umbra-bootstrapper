#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

link_dotfiles() {
  log_step "Phase 2: Clone + link Umbra configs"

  # ADR 0004: fish config is linked only when fish is the chosen shell.
  if [ "${UM_SHELL:-zsh}" = "fish" ]; then
    symlink_with_backup "$UM_ENV_DIR/shells/fish/config.fish" "$HOME/.config/fish/config.fish"
    symlink_with_backup "$UM_ENV_DIR/shells/fish/conf.d" "$HOME/.config/fish/conf.d"
    symlink_with_backup "$UM_ENV_DIR/shells/fish/functions" "$HOME/.config/fish/functions"
  fi

  symlink_with_backup "$UM_ENV_DIR/shells/zsh/zshrc" "$HOME/.zshrc"
  symlink_with_backup "$UM_ENV_DIR/shells/zsh" "$HOME/.config/zsh"

  symlink_with_backup "$UM_ENV_DIR/nvim" "$HOME/.config/nvim"

  symlink_with_backup "$UM_ENV_DIR/config/fastfetch" "$HOME/.config/fastfetch"

  log_info "Symlinks created."
}

if [ "${1:-}" = "--run" ]; then
  link_dotfiles
fi
