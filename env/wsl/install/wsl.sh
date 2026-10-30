#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# .wslconfig on the Windows host is global, so it is written only on request (ADR 0024).
UM_ENABLE_WSLCONFIG="${UM_ENABLE_WSLCONFIG:-0}"

# UM_IS_WSL=1|0 overrides the detection (used by container tests).
is_wsl() {
  case "${UM_IS_WSL:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  grep -qi microsoft /proc/version 2>/dev/null
}

# Locate the Windows user profile dir (as a Linux path) via interop.
windows_userprofile() {
  local win_path=""
  if ensure_cmd wslvar; then
    win_path="$(wslvar USERPROFILE 2>/dev/null || true)"
  fi
  if [ -z "$win_path" ] && [ -x /mnt/c/Windows/System32/cmd.exe ]; then
    # Run from a Windows-accessible cwd to avoid UNC-path warnings
    win_path="$(cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || true)"
  fi
  if [ -z "$win_path" ]; then
    return 1
  fi
  wslpath -u "$win_path" 2>/dev/null
}

configure_wsl_conf() {
  log_info "Merging /etc/wsl.conf (systemd, interop, automount metadata)..."

  # Keep the default user set at first boot, or use the invoking user, so a restart never
  # drops back to root. Other sections and keys stay as they are (ADR 0024).
  local default_user=()
  if ! grep -qi '^default[[:space:]]*=' /etc/wsl.conf 2>/dev/null && [ "$(id -u)" -ne 0 ]; then
    default_user=(user default "$(id -un)")
  fi
  wsl_conf_merge \
    boot systemd true \
    network generateHosts true \
    network generateResolvConf true \
    interop enabled true \
    interop appendWindowsPath true \
    automount enabled true \
    automount root /mnt/ \
    automount options '"metadata,umask=22,fmask=11"' \
    "${default_user[@]}"
}

configure_wslconfig() {
  # NAT + localhostForwarding is the default: it is what makes servers
  # started inside WSL reachable from Windows at localhost:<port>.
  # mirrored mode is known to break localhost connectivity (timeouts) on
  # many Windows builds / VPN setups, so it is opt-in via
  # UM_WSL_NETWORKING=mirrored.
  local mode="${UM_WSL_NETWORKING:-nat}"

  local profile wslconfig
  if ! profile="$(windows_userprofile)" || [ -z "$profile" ]; then
    log_warn "Could not locate the Windows user profile via interop; skipping .wslconfig."
    log_warn "Create %USERPROFILE%\\.wslconfig manually with: [wsl2] networkingMode=NAT, localhostForwarding=true, dnsTunneling=true, autoProxy=true"
    return 0
  fi

  wslconfig="$profile/.wslconfig"
  log_info "Configuring $wslconfig (networking: $mode, DNS tunneling, auto proxy)..."

  if [ -f "$wslconfig" ]; then
    cp "$wslconfig" "${wslconfig}.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Existing .wslconfig backed up."
  fi

  if [ "$mode" = "mirrored" ]; then
    set_ini_key "$wslconfig" "wsl2" "networkingMode" "mirrored"
    # Lets WSL processes reach Windows services via 127.0.0.1 in mirrored mode
    set_ini_key "$wslconfig" "experimental" "hostAddressLoopback" "true"
    log_warn "networkingMode=mirrored requires Windows 11 22H2+ and is known to break localhost on some setups."
    log_warn "If localhost times out after this, re-run with UM_WSL_NETWORKING=nat."
  else
    set_ini_key "$wslconfig" "wsl2" "networkingMode" "NAT"
    set_ini_key "$wslconfig" "wsl2" "localhostForwarding" "true"
  fi
  set_ini_key "$wslconfig" "wsl2" "dnsTunneling" "true"
  set_ini_key "$wslconfig" "wsl2" "autoProxy" "true"

  log_info ".wslconfig updated:"
  sed 's/^/    /' "$wslconfig" >&2
}

check_filesystem_location() {
  case "$UM_ENV_DIR" in
    /mnt/*)
      log_warn "==============================================================="
      log_warn "PERFORMANCE WARNING: Umbra lives under $UM_ENV_DIR (NTFS)."
      log_warn "Cross-OS file I/O in WSL2 is 10-20x slower than the native"
      log_warn "ext4 filesystem. Move your projects to the Linux side, e.g.:"
      log_warn "  move the umbra checkout to ~/dev/umbra"
      log_warn "==============================================================="
      ;;
  esac
  case "$PWD" in
    /mnt/*)
      log_warn "You are running from $PWD (Windows NTFS mount). Prefer ~/ for repos."
      ;;
  esac
}

configure_wsl() {
  log_step "Phase 10: WSL interop & networking optimizations"

  if ! is_wsl; then
    log_info "Not running under WSL; skipping WSL configuration."
    return 0
  fi

  configure_wsl_conf
  if [ "$UM_ENABLE_WSLCONFIG" = "1" ]; then
    configure_wslconfig
    log_warn ".wslconfig applies once every distro has stopped."
  else
    log_info "Windows .wslconfig left alone. Recommended: [wsl2] networkingMode=NAT, localhostForwarding=true, dnsTunneling=true, autoProxy=true (--enable-wslconfig applies them)."
  fi
  check_filesystem_location

  if [ "$UM_WSL_CONF_CHANGED" = "1" ]; then
    log_warn "/etc/wsl.conf changed. Restart this distro to apply it: wsl.exe --terminate ${WSL_DISTRO_NAME:-<distro>}"
  fi
}

if [ "${1:-}" = "--run" ]; then
  configure_wsl
fi
