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

# Opt-in components (install.sh, ADR 0017, 0018) run only when UM_COMPONENTS names them,
# so a plain `bootstrap.sh --yes` installs what it always did.
UM_OPTIN_COMPONENTS="desktop um vault ollama"

# component_enabled <name>: true unless excluded by UM_COMPONENTS (allow-list) or UM_SKIP.
component_enabled() {
  local name="$1"
  if [ -n "$UM_COMPONENTS" ] && [[ ",$UM_COMPONENTS," != *",$name,"* ]]; then
    return 1
  fi
  if [[ " $UM_OPTIN_COMPONENTS " == *" $name "* ]] && [[ ",$UM_COMPONENTS," != *",$name,"* ]]; then
    return 1
  fi
  [[ ",$UM_SKIP," != *",$name,"* ]]
}

# run_priv <command...>: runs a command as root (ADR 0021): directly when already root, otherwise
# through sudo. Returns 77 with the reason when neither works. The only sudo in the installer,
# apart from its copy in install.sh.
run_priv() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; return; fi
  if command -v sudo >/dev/null 2>&1; then
    if sudo -n true 2>/dev/null; then sudo -n "$@"; return; fi
    # sudo prompts on the terminal, so a terminal on stdin or stderr is enough (pipes into tee).
    if [ -t 0 ] || [ -t 2 ]; then sudo "$@"; return; fi
  fi
  log_error "need root for: $*"
  log_error "no usable sudo for user $(id -un) (installed: $(command -v sudo >/dev/null 2>&1 && echo yes || echo no), groups: $(id -nG))"
  return 77
}

# phase_gate <id> <failure message> <command...>: a side-effect-free postcondition (ADR 0023).
phase_gate() {
  local id="$1" msg="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    log_info "gate $id: ok"
    return 0
  fi
  log_error "gate $id failed: $msg"
  return 1
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
  ' "$file" > "$tmp" && cat "$tmp" > "$file" && rm -f "$tmp"
}

# wsl_conf_merge <section> <key> <value> ...: sets keys in /etc/wsl.conf and keeps everything else
# (ADR 0024). Writes, with one backup, only when something changes; UM_WSL_CONF_CHANGED is 1 after
# a write and 0 otherwise.
UM_WSL_CONF_CHANGED=0
wsl_conf_merge() {
  local tmp
  tmp="$(mktemp)"
  if [ -f /etc/wsl.conf ]; then
    cp /etc/wsl.conf "$tmp"
  fi
  while [ $# -ge 3 ]; do
    set_ini_key "$tmp" "$1" "$2" "$3"
    shift 3
  done
  UM_WSL_CONF_CHANGED=0
  if ! cmp -s "$tmp" /etc/wsl.conf; then
    if [ -f /etc/wsl.conf ]; then
      run_priv cp /etc/wsl.conf "/etc/wsl.conf.backup.$(date +%Y%m%d_%H%M%S)" || { rm -f "$tmp"; return 1; }
    fi
    run_priv install -m 0644 -o root -g root "$tmp" /etc/wsl.conf || { rm -f "$tmp"; return 1; }
    UM_WSL_CONF_CHANGED=1
  fi
  rm -f "$tmp"
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

# have_cmds <name...>: all of them exist (`command -v a b` succeeds when any does).
have_cmds() {
  local c
  for c in "$@"; do
    ensure_cmd "$c" || return 1
  done
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

# pin-downloads (ADR 0006): sha256 of a pinned URL, from install/checksums.sha256; empty if absent.
pinned_sha256() {
  awk -v url="$1" '$2 == url { print $1; exit }' "$UM_ENV_DIR/install/checksums.sha256" 2>/dev/null
}

# verify_sha256 <file> <expected>: true only when the file's sha256 is the expected one.
verify_sha256() {
  [ -n "$2" ] && [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$2" ]
}

# Install a single binary from a GitHub release asset into ~/.local/bin.
# Handles .tar.gz/.tgz, .zip and raw binary assets. The download is checked against the
# expected sha256 before it is unpacked; a missing or wrong hash refuses the install.
# Usage: install_release_bin <binary-name> <asset-url> <sha256>
install_release_bin() {
  local name="$1" url="$2" sha="${3:-}" tmp bin
  if ensure_cmd "$name"; then
    return 0
  fi
  if [ -z "$sha" ]; then
    log_warn "No pinned sha256 for $url; refusing to install $name."
    return 1
  fi
  log_info "Installing $name from $url"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/asset" "$url" || { rm -rf "$tmp"; log_warn "Download failed for $name"; return 1; }
  if ! verify_sha256 "$tmp/asset" "$sha"; then
    rm -rf "$tmp"
    log_warn "sha256 mismatch for $url; refusing to install $name."
    return 1
  fi
  case "$url" in
    *.tar.gz|*.tgz)
      tar -xz -C "$tmp" -f "$tmp/asset" || { rm -rf "$tmp"; log_warn "Unpacking failed for $name"; return 1; }
      rm -f "$tmp/asset"
      ;;
    *.zip)
      unzip -q "$tmp/asset" -d "$tmp" || { rm -rf "$tmp"; log_warn "Unpacking failed for $name"; return 1; }
      rm -f "$tmp/asset"
      ;;
    *)
      mv "$tmp/asset" "$tmp/$name"
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
  # Phase 1 (ADR 0013): umbra, generated from brand/tokens, is the default theme.
  if [ "$UM_NONINTERACTIVE" = "1" ] || ! is_tty; then
    UM_THEME="umbra"
    return 0
  fi
  log_info "Choose a Starship theme:"
  echo "1) umbra"
  echo "2) default"
  echo "3) tron"
  echo "4) cyber"
  echo "5) eva01"
  echo "6) minimal"
  read -r -p "Select [1-6] (default 1): " choice </dev/tty
  case "$choice" in
    1|"") UM_THEME="umbra" ;;
    2) UM_THEME="default" ;;
    3) UM_THEME="tron" ;;
    4) UM_THEME="cyber" ;;
    5) UM_THEME="eva01" ;;
    6) UM_THEME="minimal" ;;
    *) UM_THEME="umbra" ;;
  esac
}

export UM_ENV_DIR UM_NONINTERACTIVE UM_VERBOSE UM_SHELL UM_THEME UM_ENABLE_K8S UM_MODE UM_COMPONENTS UM_SKIP

UM_AI_REPO_HTTPS="${UM_AI_REPO_HTTPS:-https://github.com/Robertcl795/umbra-ai.git}"
UM_AI_REPO_SSH="${UM_AI_REPO_SSH:-git@github.com:Robertcl795/umbra-ai.git}"

# find_umbra_ai: prints the umbra-ai checkout (ADR 0018): UM_AI_DIR, then the umbrella's ai/
# submodule next to the bootstrapper, then the clone made by the Umbra AI item
# (UM_AI_CLONE_DIR). Returns 1 when none exists.
UM_AI_CLONE_DIR="${UM_AI_CLONE_DIR:-$HOME/.local/share/umbra/umbra-ai}"
find_umbra_ai() {
  local base d
  base="$(cd -- "$UM_ENV_DIR/../.." && pwd)"
  for d in ${UM_AI_DIR:+"$UM_AI_DIR"} "$base/../ai" "$UM_AI_CLONE_DIR"; do
    if [ -d "$d/cli" ] && [ -d "$d/toolkit/ai-standard" ]; then
      (cd -- "$d" && pwd)
      return 0
    fi
  done
  return 1
}

# clone_umbra_ai: clones umbra-ai with the user's own credentials (ADR 0018). Runs in the user's
# session, so the clone lands in the user's home. Never starts a login.
clone_umbra_ai() {
  mkdir -p "$(dirname "$UM_AI_CLONE_DIR")"
  GIT_TERMINAL_PROMPT=0 git clone -q --depth=1 "$UM_AI_REPO_HTTPS" "$UM_AI_CLONE_DIR" 2>/dev/null \
    || GIT_SSH_COMMAND="ssh -o BatchMode=yes" git clone -q --depth=1 "$UM_AI_REPO_SSH" "$UM_AI_CLONE_DIR" 2>/dev/null \
    || log_warn "Could not clone umbra-ai; its components will be skipped."
}

# find_ai_standard: prints the toolkit/ai-standard directory of umbra-ai, or returns 1.
find_ai_standard() {
  local d
  d="$(find_umbra_ai)" || return 1
  echo "$d/toolkit/ai-standard"
}
