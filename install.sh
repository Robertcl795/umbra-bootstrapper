#!/usr/bin/env bash
# install.sh — the single Umbra command (ADR 0014, 0016–0018).
#
#   curl -fsSL https://raw.githubusercontent.com/Robertcl795/umbra-bootstrapper/main/install.sh | bash
#
# Detects the platform (WSL Ubuntu/Arch, native Ubuntu/Arch, Omarchy), shows a component selector
# (gum, pinned and sha256-checked) and hands the selection to env/wsl/bootstrap.sh.
# Flags (no selector, no gum download): --yes, --profile personal|work, --components a,b,
# --skip c. UM_SELECT=<item ids> selects items without a menu. --dry-run prints the platform and
# the selection and changes nothing. Other flags (--shell, --theme, …) go to bootstrap.sh.
set -euo pipefail

UM_BOOTSTRAPPER_REPO="${UM_BOOTSTRAPPER_REPO:-https://github.com/Robertcl795/umbra-bootstrapper.git}"
UM_BRANCH="${UM_BRANCH:-main}"
UM_THEME_REPO="${UM_THEME_REPO:-https://github.com/Robertcl795/omarchy-umbra-theme.git}"

SOURCE_PATH="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
[ -n "$SOURCE_PATH" ] && [ -f "$SOURCE_PATH" ] && SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"

# ---------------------------------------------------------------------------
# Piped from curl: fetch the bootstrapper, then run its install.sh.
# ---------------------------------------------------------------------------
if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/env/wsl/bootstrap.sh" ]; then
  dest="${UM_BOOTSTRAPPER_DIR:-$HOME/.local/share/umbra/bootstrapper}"
  echo "[INFO] Fetching the Umbra bootstrapper into $dest (branch: $UM_BRANCH)..." >&2
  if ! command -v git >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get install -y git
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --noconfirm --needed git
    else
      echo "[ERROR] git is missing and no supported package manager was found." >&2
      exit 1
    fi
  fi
  if [ -d "$dest/.git" ]; then
    git -C "$dest" pull -q --ff-only || echo "[WARN] Could not update $dest; using it as it is." >&2
  else
    mkdir -p "$(dirname "$dest")"
    git clone -q --depth=1 --branch "$UM_BRANCH" "$UM_BOOTSTRAPPER_REPO" "$dest"
  fi
  if [ ! -t 0 ] && [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null; then
    exec bash "$dest/install.sh" "$@" </dev/tty
  fi
  exec bash "$dest/install.sh" "$@"
fi

# common.sh sets its own SCRIPT_DIR; keep the bootstrapper root separately.
BOOT_ROOT="$SCRIPT_DIR"
export UM_ENV_DIR="$BOOT_ROOT/env/wsl"
# shellcheck source=env/wsl/install/common.sh
source "$UM_ENV_DIR/install/common.sh"
# shellcheck source=env/wsl/install/selector.sh
source "$UM_ENV_DIR/install/selector.sh"

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
explicit=0 yes=0 dry_run=0 fetch_only=0 profile="${UM_MODE:-}" comps="" skip="${UM_SKIP:-}"
pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|--noninteractive) yes=1 explicit=1; shift ;;
    --profile)
      case "${2:-}" in
        personal|work) profile="$2" ;;
        *) die "--profile must be personal or work" ;;
      esac
      explicit=1; shift 2 ;;
    --components) comps="${2:?--components needs a list}"; explicit=1; shift 2 ;;
    --skip) skip="${2:?--skip needs a list}"; explicit=1; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --fetch-gum) fetch_only=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) pass+=("$1"); shift ;;
  esac
done
[ -z "${UM_SELECT:-}" ] || explicit=1
[ "${UM_NONINTERACTIVE:-0}" != 1 ] || yes=1

interactive=0
if [ "$explicit" = 0 ] && [ "$yes" = 0 ] && [ -t 1 ] && { : </dev/tty; } 2>/dev/null; then
  interactive=1
fi

UM_GUM_DIR="$(mktemp -d)"
export UM_GUM_DIR
trap 'rm -rf "$UM_GUM_DIR"' EXIT

# Test hook: download and check gum only.
if [ "$fetch_only" = 1 ]; then
  gum_bin="$(fetch_gum)" || exit 1
  "$gum_bin" --version
  exit 0
fi

platform="$(um_platform)" || die "Unsupported system. Umbra supports Ubuntu and Arch (WSL or native) and Omarchy."
log_info "Platform: $platform"

gum_bin=""
if [ "$interactive" = 1 ]; then
  gum_bin="$(fetch_gum)" || die "Could not get a verified gum $UM_GUM_VERSION; run again with --yes (and --components) to skip the menu."
fi

# Profile: flag, UM_MODE, the menu, or personal.
if [ -z "$profile" ]; then
  if [ "$interactive" = 1 ]; then
    profile="$("$gum_bin" choose --header="Umbra profile" personal work </dev/tty)" || exit 1
  else
    profile=personal
  fi
fi

# ---------------------------------------------------------------------------
# Selection → --components
# ---------------------------------------------------------------------------
access=0
if umbra_ai_access; then access=1; fi

if [ -z "$comps" ]; then
  if [ -n "${UM_SELECT:-}" ]; then
    ids="$UM_SELECT"
  elif [ "$interactive" = 1 ]; then
    ids="$(select_with_gum "$gum_bin" "$platform" "$(selector_defaults "$platform" "$access")" "$access")" || exit 1
  else
    ids="$(selector_defaults "$platform" "$access")"
  fi
  if [[ ",$ids," == *",umbra-ai,"* ]] && [ "$access" = 0 ]; then
    log_warn "$UM_AI_PRIVATE_MSG"
    ids="$(echo ",$ids," | sed 's/,umbra-ai,/,/; s/^,//; s/,$//')"
  fi
  [ -n "$ids" ] || die "Nothing selected."
  comps="$(items_to_components "$platform" "$ids")"
  [ -n "$comps" ] || die "Nothing selected that $platform offers."
elif [ "$access" = 0 ] && [[ ",$comps," =~ ,(um|vault|ai-standard), ]]; then
  log_warn "$UM_AI_PRIVATE_MSG"
fi

if [ "$dry_run" = 1 ]; then
  echo "platform=$platform profile=$profile components=$comps skip=$skip ai_access=$access"
  exit 0
fi

# Umbra AI selected and not here yet: clone it with the user's own credentials (ADR 0018).
if [ "$access" = 1 ] && [[ ",$comps," =~ ,(um|vault|ai-standard), ]] && ! find_umbra_ai >/dev/null 2>&1; then
  log_info "Cloning umbra-ai into $UM_AI_CLONE_DIR"
  mkdir -p "$(dirname "$UM_AI_CLONE_DIR")"
  GIT_TERMINAL_PROMPT=0 git clone -q --depth=1 "$UM_AI_REPO_HTTPS" "$UM_AI_CLONE_DIR" 2>/dev/null \
    || GIT_SSH_COMMAND="ssh -o BatchMode=yes" git clone -q --depth=1 "$UM_AI_REPO_SSH" "$UM_AI_CLONE_DIR" \
    || log_warn "Could not clone umbra-ai; its components will be skipped."
fi

# ---------------------------------------------------------------------------
# Omarchy: the theme comes from its repo (ADR 0012, 0014; O3), the rest from bootstrap.sh.
# ---------------------------------------------------------------------------
omarchy_theme() {
  local dir="$HOME/.config/omarchy/themes/umbra" src="$BOOT_ROOT/themes/omarchy/umbra"
  if command -v omarchy >/dev/null 2>&1 \
    && GIT_TERMINAL_PROMPT=0 timeout 15 git ls-remote -q "$UM_THEME_REPO" HEAD >/dev/null 2>&1; then
    log_info "Installing the Umbra theme: omarchy theme install $UM_THEME_REPO"
    # `omarchy theme install` clones into ~/.config/omarchy/themes/umbra and applies it
    # (observed on Omarchy 4, read-only, 2026-10-29).
    omarchy theme install "$UM_THEME_REPO"
    return 0
  fi
  log_warn "Theme repo not reachable; installing the bundled copy into $dir."
  if [ ! -d "$dir/.git" ]; then
    mkdir -p "$dir"
    cp -f "$src/colors.toml" "$src/icons.theme" "$dir/"
  fi
  if command -v omarchy >/dev/null 2>&1; then
    omarchy theme set umbra
  fi
}

args=(--profile "$profile" --components "$comps")
[ -z "$skip" ] || args+=(--skip "$skip")
[ "$yes" = 0 ] || args+=(--yes)
# After the menu, bootstrap.sh does not ask about Kubernetes again. Without the menu the
# chezmoi data stays exactly what the equivalent bootstrap.sh flags give (Gate 3).
if [ "$interactive" = 1 ] && [ -z "${UM_ENABLE_K8S:-}" ]; then
  if [[ ",$comps," == *",k8s,"* ]]; then export UM_ENABLE_K8S=1; else export UM_ENABLE_K8S=0; fi
fi

if [ "$platform" = omarchy ]; then
  export UM_OS=omarchy
  omarchy_theme
fi

log_info "Profile: $profile · components: $comps${skip:+ · skip: $skip}"
exec bash "$UM_ENV_DIR/bootstrap.sh" "${args[@]}" "${pass[@]}"
