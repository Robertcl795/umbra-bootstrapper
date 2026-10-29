#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

install_starship() {
  log_step "Phase 4: Prompt themes (Starship)"

  if ! ensure_cmd starship; then
    log_info "Installing Starship via official installer."
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y
  fi

  # chezmoi-unlink (ADR 0006): ~/.config/starship.toml is rendered by chezmoi from the
  # `theme` value (env/dot_config/starship.toml.tmpl); switch with
  # `UM_THEME=<name> chezmoi init --apply`.
  log_info "Starship installed (theme: ${UM_THEME:-default}, managed by chezmoi)."
}

if [ "${1:-}" = "--run" ]; then
  install_starship
fi
