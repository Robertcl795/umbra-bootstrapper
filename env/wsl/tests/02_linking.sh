#!/usr/bin/env bash
set -euo pipefail

check_link() {
  if [ ! -L "$1" ]; then
    echo "Expected symlink: $1" >&2
    exit 1
  fi
}

check_link "$HOME/.config/nvim"
# ADR 0004: fish config is linked only when fish is the chosen shell.
if [ "${UM_SHELL:-zsh}" = "fish" ]; then
  check_link "$HOME/.config/fish/config.fish"
fi
check_link "$HOME/.zshrc"
check_link "$HOME/.config/starship.toml"
check_link "$HOME/.config/zellij/config.kdl"
