#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Each install/*.sh runs as its own `bash foo.sh --run` process, so PATH
# exports made there (rustup, fnm, uv, claude, opencode, ...) never reach
# this process. Pick up the same install dirs before checking commands.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.opencode/bin:$PATH"

# Print one row. Presence is a plain `command -v` check; version is only
# attempted for flags we know are quick and non-interactive, and is always
# wrapped in `timeout` so a TUI tool (e.g. sshs, yazi) can never hang the
# summary if it doesn't actually support the flag.
summary_row() {
  local label="$1" cmd="$2" flag="${3:-}"
  local alt="${4:-}"

  local found_cmd=""
  if ensure_cmd "$cmd"; then
    found_cmd="$cmd"
  elif [ -n "$alt" ] && ensure_cmd "$alt"; then
    found_cmd="$alt"
  fi

  if [ -z "$found_cmd" ]; then
    printf '  %-13s %-10s\n' "$label" "not found"
    return 0
  fi

  local version=""
  if [ -n "$flag" ] && ensure_cmd timeout; then
    # $flag may be a multi-word command (e.g. "version --client=true");
    # word-split deliberately, it's always a fixed literal we pass in below.
    # shellcheck disable=SC2086
    version="$(timeout 3 "$found_cmd" $flag 2>/dev/null | head -n1 || true)"
  fi
  printf '  %-13s %-10s %s\n' "$label" "installed" "${version:+($version)}"
}

print_summary() {
  log_step "Installed tools summary"

  echo "" >&2
  echo "Shell + prompt:" >&2
  summary_row "shell" "$UM_SHELL" "--version"
  summary_row "starship" starship --version
  echo "  theme:        $UM_THEME" >&2

  echo "" >&2
  echo "Modern CLI:" >&2
  summary_row "eza" eza --version exa
  summary_row "bat" bat --version batcat
  summary_row "fd" fd --version fdfind
  summary_row "ripgrep" rg --version
  summary_row "fzf" fzf --version
  summary_row "zoxide" zoxide --version
  summary_row "tldr" tldr "" tealdeer
  summary_row "zellij" zellij --version
  summary_row "just" just --version
  summary_row "lazygit" lazygit --version
  summary_row "lazydocker" lazydocker
  summary_row "glow" glow --version
  summary_row "duf" duf --version
  summary_row "yazi" yazi
  summary_row "sshs" sshs
  summary_row "lnav" lnav -V
  summary_row "fastfetch" fastfetch --version

  echo "" >&2
  echo "Editor:" >&2
  summary_row "neovim" nvim --version

  echo "" >&2
  echo "Language toolchains:" >&2
  summary_row "rustup" rustc --version
  summary_row "fnm" fnm --version
  summary_row "uv" uv --version

  if [ "${UM_ENABLE_K8S:-0}" = "1" ]; then
    echo "" >&2
    echo "Kubernetes:" >&2
    summary_row "kubectl" kubectl "version --client=true"
    summary_row "helm" helm version
    summary_row "k3d" k3d version
  fi

  echo "" >&2
  echo "AI tooling:" >&2
  summary_row "claude" claude --version
  summary_row "opencode" opencode --version
  summary_row "gh" gh --version

  echo "" >&2
  log_info "Full checkpoint: tests/99_smoke.sh"
}

if [ "${1:-}" = "--run" ]; then
  print_summary
fi
