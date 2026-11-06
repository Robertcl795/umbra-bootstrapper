#!/usr/bin/env bash
# default.sh — Make default (plan installer-packages-shell, T4): what umbra-setup's Make default
# screen runs, and only after the user confirmed it there.
#   --status         login=<login shell>, and on WSL wt_default= and wt_pwsh7= (profile guids)
#   --shell <name>   make zsh or fish the login shell (/etc/shells, then usermod -s or chsh)
#   --wt-pwsh7       make PowerShell 7 Windows Terminal's default profile: umbra-setup
#                    --wt-default-pwsh7 backs settings.json up and changes only defaultProfile
#                    (ADR 0043, amended)
# Sourced without arguments it only defines its functions (env/wsl/tests/unit_default_shell.sh).
# Tests set UM_SHELLS_FILE (for /etc/shells) and the terminal.sh overrides.
set -euo pipefail

DEFAULT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]:-${0:-}}")" && pwd)"
# shellcheck disable=SC1090,SC1091
source "$DEFAULT_DIR/../terminal.sh"

UM_SHELLS_FILE="${UM_SHELLS_FILE:-/etc/shells}"

# me: this user (USER is not set in every session, e.g. wsl.exe -u).
me() { id -un; }

# login_shell: the user's login shell from the passwd database.
login_shell() { getent passwd "$(me)" | cut -d: -f7; }

# setup_bin: the umbra-setup that reads and changes settings.json.
setup_bin() {
  if [ -n "${UM_SETUP_BIN:-}" ]; then echo "$UM_SETUP_BIN"; else command -v umbra-setup || echo "$HOME/.local/bin/umbra-setup"; fi
}

default_status() {
  echo "login=$(login_shell)"
  localappdata || return 0
  local f out
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    out="$("$(setup_bin)" --wt-status "$f" 2>/dev/null)" || continue
    echo "wt_settings=$f"
    sed -n 's/^default=/wt_default=/p; s/^pwsh7=/wt_pwsh7=/p' <<<"$out"
    return 0
  done < <(wt_settings)
}

# default_shell_set <zsh|fish>
default_shell_set() {
  local name="$1" path
  case "$name" in zsh | fish) ;; *) log_error "Make default: unknown shell '$name'"; return 2 ;; esac
  if [ "${UM_OS:-}" = omarchy ]; then
    log_warn "Omarchy keeps its own login shell (ADR 0011); nothing changed."
    return 1
  fi
  path="$(command -v "$name")" || { log_error "$name is not installed."; return 1; }
  if [ "$(login_shell)" = "$path" ]; then
    log_info "$name is already your login shell."
    return 0
  fi
  # chsh and usermod refuse a shell missing from /etc/shells.
  if ! grep -qx -- "$path" "$UM_SHELLS_FILE" 2>/dev/null; then
    echo "$path" | run_priv tee -a "$UM_SHELLS_FILE" >/dev/null
  fi
  if run_priv usermod -s "$path" "$(me)" 2>/dev/null || chsh -s "$path"; then
    log_info "Your login shell is now $name ($path); it applies to new sessions."
    return 0
  fi
  log_warn "Could not change the login shell. Run: chsh -s $path"
  return 1
}

default_wt_pwsh7() {
  localappdata || { log_warn "The Windows side is not reachable; Windows Terminal unchanged."; return 1; }
  local f out rc
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    out="$("$(setup_bin)" --wt-status "$f" 2>/dev/null)" || continue
    if ! grep -q '^pwsh7=.' <<<"$out"; then
      log_warn "Windows Terminal does not list PowerShell 7 yet: open Windows Terminal once, then: Settings > Startup > Default profile: PowerShell."
      return 3
    fi
    rc=0
    out="$("$(setup_bin)" --wt-default-pwsh7 "$f")" || rc=$?
    if [ "$rc" = 0 ]; then
      log_info "Windows Terminal opens PowerShell 7 by default now. Your old settings: ${out#backup=}"
    fi
    return "$rc"
  done < <(wt_settings)
  log_warn "No Windows Terminal settings.json found; Windows Terminal unchanged."
  return 1
}

case "${1:-}" in
  --status) default_status ;;
  --shell) default_shell_set "${2:?--shell needs zsh or fish}" ;;
  --wt-pwsh7) default_wt_pwsh7 ;;
esac
