#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

detect_os() {
  log_step "Phase 0: Preflight & OS detection"

  # UM_IS_WSL=1|0 overrides the detection (used by container tests).
  local wsl=0
  case "${UM_IS_WSL:-}" in
    1) wsl=1 ;;
    0) wsl=0 ;;
    *) grep -qi microsoft /proc/version 2>/dev/null && wsl=1 ;;
  esac
  if [ "$wsl" != "1" ]; then
    log_info "Not running under WSL: native install, no WSL tuning (ADR 0017)."
  fi

  if [ ! -f /etc/os-release ]; then
    die "Cannot detect OS: /etc/os-release not found."
  fi
  . /etc/os-release
  # UM_OS (install.sh, tests) overrides the detected ID.
  ID="${UM_OS:-${ID:-}}"

  case "${ID:-}" in
    ubuntu)
      export UM_OS="ubuntu"
      ;;
    arch)
      export UM_OS="arch"
      ;;
    omarchy)
      export UM_OS="omarchy"
      ;;
    *)
      die "Unsupported OS: ${ID:-unknown}. Supported: Ubuntu and Arch (WSL or native), Omarchy."
      ;;
  esac

  log_info "Detected OS: $UM_OS"

  if ensure_cmd curl || ensure_cmd wget; then
    log_info "Network tools available."
  else
    die "Missing curl/wget. Please install one before continuing."
  fi

  if ! (curl -fsSL https://example.com >/dev/null 2>&1 || wget -qO- https://example.com >/dev/null 2>&1); then
    die "Network check failed. Please verify internet connectivity."
  fi

  if ! ensure_cmd sudo; then
    die "sudo is required for package installation."
  fi
}

if [ "${1:-}" = "--run" ]; then
  detect_os
fi
