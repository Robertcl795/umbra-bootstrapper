#!/usr/bin/env bash
# wsl_detect.sh — what this WSL can do, read from the machine, never inferred from a version number.
# Facts and sources: docs/bootstrap-fix/wsl-versions.md in the Umbra umbrella.
# Reads only. Sourced by P0 and the doctor; `bash wsl_detect.sh --report` prints key=value lines.
# Every value degrades to `unknown`, `no` or `unset`; nothing here fails the caller.
# Test seams: UM_WSL_CONF, UM_WSL_PROC, UM_WSL_UNAME, UM_WSL_TIMEOUT, and PATH for a fake wsl.exe.

UM_WSL_CONF="${UM_WSL_CONF:-/etc/wsl.conf}"
UM_WSL_PROC="${UM_WSL_PROC:-/proc}"
UM_WSL_TIMEOUT="${UM_WSL_TIMEOUT:-10}"

# wsl_conf_get <section> <key>: the value in wsl.conf, unquoted; empty when absent.
wsl_conf_get() {
  [ -r "$UM_WSL_CONF" ] || return 0
  awk -v s="$1" -v k="$2" '
    BEGIN { section = tolower("[" s "]"); key = tolower(k) }
    {
      line = $0
      sub(/\r$/, "", line)
      gsub(/^[ \t]+|[ \t]+$/, "", line)
    }
    line ~ /^[#;]/ { next }
    line ~ /^\[/ { inside = (tolower(line) == section); next }
    inside && index(line, "=") {
      eq = index(line, "=")
      name = substr(line, 1, eq - 1)
      value = substr(line, eq + 1)
      gsub(/[ \t]/, "", name)
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      gsub(/"/, "", value)
      if (tolower(name) == key) found = value
    }
    END { print found }
  ' "$UM_WSL_CONF"
}

wsl_mount_root() {
  local root
  root="$(wsl_conf_get automount root)"
  root="${root:-/mnt/}"
  echo "${root%/}/"
}

# wsl_win_exe <name> <path under the drive>: PATH first; appendWindowsPath=false leaves it out.
wsl_win_exe() {
  local fallback
  if command -v "$1" 2>/dev/null; then
    return 0
  fi
  fallback="$(wsl_mount_root)c/$2"
  [ -e "$fallback" ] && echo "$fallback"
}

wsl_bool() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true) echo yes ;;
    false) echo no ;;
  esac
}

# wsl_status <wanted> <live>: unset, unknown, honored, or pending (needs a restart of the distro).
wsl_status() {
  if [ -z "$1" ]; then
    echo unset
  elif [ "$2" = unknown ]; then
    echo unknown
  elif [ "$1" = "$2" ]; then
    echo honored
  else
    echo pending
  fi
}

# wsl.exe prints UTF-16 for its own messages, with or without a BOM, and translates its labels. So
# the bytes that are not ASCII go, and the fields are taken by position: WSL first, kernel second.
wsl_read_exe() {
  local exe out rc=0
  local -a dotted=()
  exe="$(wsl_win_exe wsl.exe Windows/System32/wsl.exe)" || return 0
  out="$(
    timeout "$UM_WSL_TIMEOUT" "$exe" --version </dev/null 2>/dev/null | LC_ALL=C tr -d '\000\r\377\376'
    exit "${PIPESTATUS[0]}"
  )" || rc=$?
  # 124 timed out; 126, 127 could not run. Any other failure ran it: an older wsl.exe rejects --version.
  case "$rc" in
    124 | 125 | 126 | 127 | 137) return 0 ;;
  esac
  UM_DET_INTEROP=yes
  [ "$rc" -eq 0 ] || return 0
  mapfile -t dotted < <(LC_ALL=C grep -aoE '[0-9]+(\.[0-9]+){2,}(-[0-9]+)?' <<<"$out" || true)
  if [ -n "${dotted[0]:-}" ]; then
    UM_DET_VERSION="${dotted[0]}"
    UM_DET_VERSION_SOURCE=wsl.exe
  fi
  UM_DET_KERNEL_REPORTED="${dotted[1]:-unknown}"
}

# wslinfo needs no interop. Not every version has every option, so an empty answer is `unknown`.
wsl_info() {
  local out
  command -v wslinfo >/dev/null 2>&1 || return 0
  out="$(timeout "$UM_WSL_TIMEOUT" wslinfo "$1" </dev/null 2>/dev/null | tr -d '\r' | head -n 1)" || return 0
  printf '%s' "$out"
}

wsl_read_windows_fs() {
  local root
  root="$(wsl_mount_root)"
  awk -v root="$root" 'index($2, root) == 1 && length($2) == length(root) + 1 && $3 != "autofs" { print $3 " " $4; exit }' \
    "$UM_WSL_PROC/mounts" 2>/dev/null
}

wsl_default_user_live() {
  local user=""
  if [ "$UM_DET_INTEROP" = yes ] && [ -n "${WSL_DISTRO_NAME:-}" ]; then
    user="$(timeout "$UM_WSL_TIMEOUT" "$(wsl_win_exe wsl.exe Windows/System32/wsl.exe)" -d "$WSL_DISTRO_NAME" --exec id -un </dev/null 2>/dev/null | tr -d '\r')" || user=""
  fi
  echo "${user:-unknown}"
}

# wsl_detect: fills UM_DET_*. Safe under `set -eu`, and a no-op outside WSL.
wsl_detect() {
  local kernel info mount want_metadata live_metadata=unknown
  UM_DET_WSL=0
  UM_DET_VM=unknown
  UM_DET_VERSION=unknown
  UM_DET_VERSION_SOURCE=none
  UM_DET_MAJOR=unknown
  UM_DET_KERNEL="${UM_WSL_UNAME:-$(uname -r)}"
  UM_DET_KERNEL_REPORTED=unknown
  UM_DET_INTEROP=no
  UM_DET_SYSTEMD=no
  UM_DET_WINDOWS_FS=none
  UM_DET_NETWORKING=unknown
  UM_DET_WSLC=no
  UM_DET_CONF_SYSTEMD="unset"
  UM_DET_CONF_INTEROP="unset"
  UM_DET_CONF_USER="unset"
  UM_DET_CONF_AUTOMOUNT="unset"

  case "${UM_IS_WSL:-}" in
    1) UM_DET_WSL=1 ;;
    0) return 0 ;;
    *) grep -qi microsoft "$UM_WSL_PROC/version" 2>/dev/null && UM_DET_WSL=1 ;;
  esac
  [ "$UM_DET_WSL" = 1 ] || return 0

  kernel="$UM_DET_KERNEL"
  case "$kernel" in
    *WSL2* | *microsoft-standard*) UM_DET_VM=2 ;;
    *Microsoft*) UM_DET_VM=1 ;;
  esac

  wsl_read_exe
  if [ "$UM_DET_VERSION" = unknown ]; then
    info="$(wsl_info --version)"
    if [[ $info =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
      UM_DET_VERSION="$info"
      UM_DET_VERSION_SOURCE=wslinfo
    fi
  fi
  if [ "$UM_DET_VERSION" != unknown ]; then
    UM_DET_MAJOR="${UM_DET_VERSION%%.*}"
  fi

  if [ "$(cat "$UM_WSL_PROC/1/comm" 2>/dev/null)" = systemd ]; then
    UM_DET_SYSTEMD=yes
  fi

  info="$(wsl_info --networking-mode)"
  if [[ $info =~ ^[a-zA-Z]+$ ]]; then
    UM_DET_NETWORKING="$info"
  fi

  if wsl_win_exe wslc.exe 'Program Files/WSL/wslc.exe' >/dev/null; then
    UM_DET_WSLC=yes
  fi

  mount="$(wsl_read_windows_fs)"
  if [ -n "$mount" ]; then
    UM_DET_WINDOWS_FS="${mount%% *}"
  fi

  UM_DET_CONF_SYSTEMD="$(wsl_status "$(wsl_bool "$(wsl_conf_get boot systemd)")" "$UM_DET_SYSTEMD")"
  UM_DET_CONF_INTEROP="$(wsl_status "$(wsl_bool "$(wsl_conf_get interop enabled)")" "$UM_DET_INTEROP")"

  info="$(wsl_conf_get user default)"
  if [ -n "$info" ]; then
    UM_DET_CONF_USER="$(wsl_status "$info" "$(wsl_default_user_live)")"
  fi

  # Only 9p shows how the options landed; other filesystems are not assumed to report them.
  want_metadata=""
  if [[ $(wsl_conf_get automount options) == *metadata* ]]; then
    want_metadata=yes
  fi
  if [ "$UM_DET_WINDOWS_FS" = 9p ]; then
    live_metadata=no
    if [[ $mount == *metadata* ]]; then
      live_metadata=yes
    fi
  fi
  UM_DET_CONF_AUTOMOUNT="$(wsl_status "$want_metadata" "$live_metadata")"
}

wsl_detect_report() {
  cat <<EOF
wsl=$UM_DET_WSL
vm=$UM_DET_VM
version=$UM_DET_VERSION
version_source=$UM_DET_VERSION_SOURCE
major=$UM_DET_MAJOR
kernel=$UM_DET_KERNEL
kernel_reported=$UM_DET_KERNEL_REPORTED
interop=$UM_DET_INTEROP
systemd_pid1=$UM_DET_SYSTEMD
windows_fs=$UM_DET_WINDOWS_FS
networking=$UM_DET_NETWORKING
wslc=$UM_DET_WSLC
conf_systemd=$UM_DET_CONF_SYSTEMD
conf_interop=$UM_DET_CONF_INTEROP
conf_user=$UM_DET_CONF_USER
conf_automount=$UM_DET_CONF_AUTOMOUNT
EOF
}

# One line for P0. Needs common.sh.
wsl_detect_log() {
  log_info "WSL $UM_DET_VERSION ($UM_DET_VERSION_SOURCE), VM $UM_DET_VM, kernel $UM_DET_KERNEL, systemd $UM_DET_SYSTEMD, interop $UM_DET_INTEROP, Windows files $UM_DET_WINDOWS_FS, network $UM_DET_NETWORKING, wslc $UM_DET_WSLC"
}

if [ "${BASH_SOURCE[0]}" = "${0:-}" ]; then
  set -uo pipefail
  wsl_detect
  wsl_detect_report
fi
