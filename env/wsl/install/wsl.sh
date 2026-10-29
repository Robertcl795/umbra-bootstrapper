#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Remember whether the user set UM_ENABLE_WSLCONFIG before it gets its default:
# in the work profile, .wslconfig on the Windows host is edited only on request.
UM_WSLCONFIG_EXPLICIT="${UM_ENABLE_WSLCONFIG+set}"
UM_ENABLE_WSLCONFIG="${UM_ENABLE_WSLCONFIG:-1}"

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

# Set key=value inside an INI section, preserving the rest of the file.
# Usage: set_ini_key <file> <section> <key> <value>
set_ini_key() {
  local file="$1" section="$2" key="$3" value="$4"
  if [ ! -f "$file" ]; then
    printf '[%s]\n%s=%s\n' "$section" "$key" "$value" > "$file"
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN { in_section = 0; done = 0; seen_section = 0 }
    /^\[.*\]$/ {
      if (in_section && !done) { print key "=" value; done = 1 }
      in_section = (tolower($0) == "[" tolower(section) "]")
      if (in_section) seen_section = 1
      print
      next
    }
    {
      if (in_section && !done) {
        line = $0
        gsub(/[ \t]/, "", line)
        split(line, kv, "=")
        if (tolower(kv[1]) == tolower(key)) { print key "=" value; done = 1; next }
      }
      print
    }
    END {
      if (!seen_section) { print "[" section "]"; print key "=" value }
      else if (!done) { print key "=" value }
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

configure_wsl_conf() {
  log_info "Writing /etc/wsl.conf (systemd, interop, automount metadata)..."

  # Preserve the default user set at first boot (or fall back to the
  # invoking user) so a WSL restart never drops back to root.
  local default_user=""
  if [ -f /etc/wsl.conf ]; then
    default_user="$(awk -F= '
      /^\[/ { section = tolower($0) }
      section == "[user]" && tolower($1) ~ /^[ \t]*default[ \t]*$/ { gsub(/[ \t\r]/, "", $2); print $2; exit }
    ' /etc/wsl.conf)"
    sudo cp /etc/wsl.conf "/etc/wsl.conf.backup.$(date +%Y%m%d_%H%M%S)"
  fi
  if [ -z "$default_user" ] && [ "$(id -u)" -ne 0 ]; then
    default_user="$USER"
  fi

  sudo tee /etc/wsl.conf > /dev/null << 'EOF'
# Managed by Umbra (env/wsl/install/wsl.sh)
# Apply with: wsl --shutdown (from PowerShell), then reopen the terminal.

[boot]
systemd=true

[network]
generateHosts=true
generateResolvConf=true

[interop]
enabled=true
appendWindowsPath=true

[automount]
enabled=true
root=/mnt/
# metadata enables Linux permissions on NTFS mounts
options="metadata,umask=22,fmask=11"
EOF

  if [ -n "$default_user" ]; then
    printf '\n[user]\ndefault=%s\n' "$default_user" | sudo tee -a /etc/wsl.conf > /dev/null
    log_info "Default WSL user preserved: $default_user"
  fi
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

  if [ "$UM_ENABLE_WSLCONFIG" != "1" ]; then
    log_info "WSL host configuration disabled (UM_ENABLE_WSLCONFIG=0)."
    return 0
  fi

  configure_wsl_conf
  if [ "${UM_MODE:-personal}" = "work" ] && [ -z "$UM_WSLCONFIG_EXPLICIT" ]; then
    log_info "Work profile: leaving the Windows .wslconfig untouched (set UM_ENABLE_WSLCONFIG=1 to edit it)."
  else
    configure_wslconfig
  fi
  check_filesystem_location

  log_warn "Run 'wsl --shutdown' from PowerShell for network changes to take effect."
}

if [ "${1:-}" = "--run" ]; then
  configure_wsl
fi
