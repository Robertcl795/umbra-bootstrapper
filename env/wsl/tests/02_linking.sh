#!/usr/bin/env bash
set -euo pipefail

# chezmoi-layout (ADR 0006): the configs are files deployed by chezmoi, not symlinks.
check_managed() {
  if [ ! -e "$1" ] || [ -L "$1" ]; then
    echo "Expected a chezmoi-managed file or directory (not a symlink): $1" >&2
    exit 1
  fi
}

check_managed "$HOME/.config/nvim"
# ADR 0004: fish config is deployed only when fish is the chosen shell.
if [ "${UM_SHELL:-zsh}" = "fish" ]; then
  check_managed "$HOME/.config/fish/config.fish"
fi
check_managed "$HOME/.zshrc"
check_managed "$HOME/.config/starship.toml"
check_managed "$HOME/.config/zellij/config.kdl"

chezmoi verify || { echo "chezmoi verify: the managed files differ from the source." >&2; exit 1; }
