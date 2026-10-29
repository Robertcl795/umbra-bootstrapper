#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
UM_ENV_DIR="${UM_ENV_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"

UM_NONINTERACTIVE="${UM_NONINTERACTIVE:-0}"
UM_VERBOSE="${UM_VERBOSE:-0}"
UM_SHELL="${UM_SHELL:-}"
UM_THEME="${UM_THEME:-}"
UM_ENABLE_K8S="${UM_ENABLE_K8S:-}"
# Non-interactive mode: profile (same values as um's UM_MODE) and component selection.
UM_MODE="${UM_MODE:-personal}"
UM_COMPONENTS="${UM_COMPONENTS:-}"
UM_SKIP="${UM_SKIP:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${CYAN}==>${NC} $*" >&2; }

die() { log_error "$*"; exit 1; }

# component_enabled <name>: true unless excluded by UM_COMPONENTS (allow-list) or UM_SKIP.
component_enabled() {
  local name="$1"
  if [ -n "$UM_COMPONENTS" ] && [[ ",$UM_COMPONENTS," != *",$name,"* ]]; then
    return 1
  fi
  [[ ",$UM_SKIP," != *",$name,"* ]]
}

is_tty() { [ -t 0 ] && [ -t 1 ]; }

confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-y}"
  if [ "$UM_NONINTERACTIVE" = "1" ] || ! is_tty; then
    [ "$default" = "y" ] && return 0 || return 1
  fi
  local suffix
  if [ "$default" = "y" ]; then
    suffix="(Y/n)"
  else
    suffix="(y/N)"
  fi
  read -r -p "$prompt $suffix " reply </dev/tty
  if [ "$default" = "y" ]; then
    [[ "$reply" =~ ^[Nn]$ ]] && return 1 || return 0
  else
    [[ "$reply" =~ ^[Yy]$ ]] && return 0 || return 1
  fi
}

backup_path() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local backup="${target}.backup.${ts}"
    log_warn "Backing up $target -> $backup"
    mv "$target" "$backup"
  fi
}

symlink_with_backup() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    local current
    current="$(readlink "$dest")"
    if [ "$current" = "$src" ]; then
      return 0
    fi
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup_path "$dest"
  fi
  ln -s "$src" "$dest"
}

ensure_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run() {
  if [ "$UM_VERBOSE" = "1" ]; then
    log_step "$*"
  fi
  "$@"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "amd64" ;;
  esac
}

# Install a single binary from a GitHub release asset into ~/.local/bin.
# Handles .tar.gz/.tgz, .zip and raw binary assets.
# Usage: install_release_bin <binary-name> <asset-url>
install_release_bin() {
  local name="$1" url="$2" tmp bin
  if ensure_cmd "$name"; then
    return 0
  fi
  log_info "Installing $name from $url"
  tmp="$(mktemp -d)"
  case "$url" in
    *.tar.gz|*.tgz)
      curl -fsSL "$url" | tar -xz -C "$tmp" || { rm -rf "$tmp"; log_warn "Download failed for $name"; return 1; }
      ;;
    *.zip)
      curl -fsSL -o "$tmp/pkg.zip" "$url" && unzip -q "$tmp/pkg.zip" -d "$tmp" || { rm -rf "$tmp"; log_warn "Download failed for $name"; return 1; }
      rm -f "$tmp/pkg.zip"
      ;;
    *)
      curl -fsSL -o "$tmp/$name" "$url" || { rm -rf "$tmp"; log_warn "Download failed for $name"; return 1; }
      ;;
  esac
  # Release tarballs frequently ship a shell-completion file named after the
  # binary (fastfetch's does: usr/share/bash-completion/completions/fastfetch),
  # and find's traversal order is not guaranteed — so prefer an executable
  # under a bin/ directory, then any executable, before falling back to
  # whatever matches by name (raw single-file downloads arrive mode 0644).
  bin="$(find "$tmp" -type f \( -name "$name" -o -name "$name-*" \) -path '*/bin/*' -perm -u+x 2>/dev/null | head -1)"
  [ -n "$bin" ] || bin="$(find "$tmp" -type f \( -name "$name" -o -name "$name-*" \) -perm -u+x 2>/dev/null | head -1)"
  [ -n "$bin" ] || bin="$(find "$tmp" -type f \( -name "$name" -o -name "$name-*" \) 2>/dev/null | head -1)"
  if [ -z "$bin" ]; then
    rm -rf "$tmp"
    log_warn "No $name binary found in release asset."
    return 1
  fi
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$bin" "$HOME/.local/bin/$name"
  rm -rf "$tmp"
  log_info "$name installed to ~/.local/bin/$name"
}

select_shell() {
  if [ -n "$UM_SHELL" ]; then
    return 0
  fi
  if [ "$UM_NONINTERACTIVE" = "1" ] || ! is_tty; then
    UM_SHELL="zsh"
    return 0
  fi
  log_info "Choose a shell:"
  echo "1) fish"
  echo "2) zsh"
  read -r -p "Select [1-2] (default 2): " choice </dev/tty
  case "$choice" in
    1) UM_SHELL="fish" ;;
    2|"") UM_SHELL="zsh" ;;
    *) UM_SHELL="zsh" ;;
  esac
}

select_theme() {
  if [ -n "$UM_THEME" ]; then
    return 0
  fi
  if [ "$UM_NONINTERACTIVE" = "1" ] || ! is_tty; then
    UM_THEME="default"
    return 0
  fi
  log_info "Choose a Starship theme:"
  echo "1) default"
  echo "2) tron"
  echo "3) cyber"
  echo "4) eva01"
  echo "5) minimal"
  read -r -p "Select [1-5] (default 1): " choice </dev/tty
  case "$choice" in
    1|"") UM_THEME="default" ;;
    2) UM_THEME="tron" ;;
    3) UM_THEME="cyber" ;;
    4) UM_THEME="eva01" ;;
    5) UM_THEME="minimal" ;;
    *) UM_THEME="default" ;;
  esac
}

export UM_ENV_DIR UM_NONINTERACTIVE UM_VERBOSE UM_SHELL UM_THEME UM_ENABLE_K8S UM_MODE UM_COMPONENTS UM_SKIP
