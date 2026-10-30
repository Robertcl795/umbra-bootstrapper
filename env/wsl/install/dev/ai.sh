#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# AI tooling: Claude Code, opencode and GitHub Copilot CLI.

install_claude_cli() {
  export PATH="$HOME/.local/bin:$PATH"
  if ensure_cmd claude; then
    log_info "claude already installed: $(claude --version 2>/dev/null || true)"
    return 0
  fi
  log_info "Installing Claude Code (native installer)..."
  curl -fsSL https://claude.ai/install.sh | bash || log_warn "Claude Code install failed; retry later with: curl -fsSL https://claude.ai/install.sh | bash"
}

install_opencode_cli() {
  # Personal-only (ADR 0007, decision 11).
  if [ "${UM_MODE:-personal}" = "work" ]; then
    log_info "Work profile: opencode is personal-only; skipping."
    return 0
  fi
  export PATH="$HOME/.opencode/bin:$PATH"
  if ensure_cmd opencode; then
    log_info "opencode already installed."
    return 0
  fi
  log_info "Installing opencode..."
  curl -fsSL https://opencode.ai/install | bash || log_warn "opencode install failed; retry later with: curl -fsSL https://opencode.ai/install | bash"
}

install_gh_copilot() {
  if ! ensure_cmd gh; then
    log_info "Installing GitHub CLI..."
    case "${UM_OS:-}" in
      arch|omarchy) sudo pacman -S --noconfirm --needed github-cli ;;
      ubuntu) sudo apt-get install -y gh ;;
      *) log_warn "Unknown OS for gh install; skipping Copilot CLI."; return 0 ;;
    esac
  fi

  if gh auth status >/dev/null 2>&1; then
    if ! gh extension list 2>/dev/null | grep -q gh-copilot; then
      log_info "Installing gh-copilot extension..."
      gh extension install github/gh-copilot || log_warn "gh-copilot install failed."
    fi
  else
    log_warn "gh is not authenticated. After running 'gh auth login', install Copilot with:"
    log_warn "  gh extension install github/gh-copilot"
  fi
}

install_ai_tools() {
  log_step "Phase 9: AI tooling (claude / opencode / gh copilot)"
  install_claude_cli
  install_opencode_cli
  install_gh_copilot
}

if [ "${1:-}" = "--run" ]; then
  install_ai_tools
fi
