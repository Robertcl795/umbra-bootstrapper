#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for the Umbra WSL environment (env/wsl)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Robertcl795/umbra-bootstrapper/main/env/wsl/bootstrap.sh | bash
#   OR cloned: env/wsl/bootstrap.sh

UM_REPO="https://github.com/Robertcl795/umbra-bootstrapper.git"
UM_BRANCH="${UM_BRANCH:-main}"
SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"

# A fresh clone of the umbra-bootstrapper repo goes to UM_REPO_DIR (ADR 0014); the installer lives
# in its env/wsl/ subdirectory (UM_ENV_DIR).
UM_REPO_DIR="${UM_REPO_DIR:-$HOME/dev/umbra-bootstrapper}"
if [ -d "$SCRIPT_DIR/.git" ] || [ -d "$SCRIPT_DIR/install" ]; then
  UM_ENV_DIR="${UM_ENV_DIR:-$SCRIPT_DIR}"
else
  UM_ENV_DIR="${UM_ENV_DIR:-$UM_REPO_DIR/env/wsl}"
fi

INSTALL_ARGS=()

# Colors (optional)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_info(){ echo -e "${BLUE}[INFO]${NC} $*" >&2; }
print_success(){ echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
print_warning(){ echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
print_error(){ echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Basic arg pass-through (collect and forward to install/run.sh)
while [ $# -gt 0 ]; do
  case "$1" in
    --noninteractive|--yes) export UM_NONINTERACTIVE=1; shift ;;
    --profile)
      case "${2:-}" in
        personal|work) export UM_MODE="$2" ;;
        *) print_error "--profile must be personal or work"; exit 2 ;;
      esac
      shift 2 ;;
    --components) export UM_COMPONENTS="$2"; shift 2 ;;
    --skip) export UM_SKIP="$2"; shift 2 ;;
    --user) export UM_USERNAME="$2"; shift 2 ;;
    --shell) export UM_SHELL="$2"; shift 2 ;;
    --theme) export UM_THEME="$2"; shift 2 ;;
    --enable-k8s) export UM_ENABLE_K8S=1; shift ;;
    --disable-k8s) export UM_ENABLE_K8S=0; shift ;;
    --enable-tmux|--disable-tmux)
      print_warning "tmux support was replaced by Zellij; '$1' is deprecated and ignored."
      shift ;;
    --enable-wslconfig) export UM_ENABLE_WSLCONFIG=1; shift ;;
    --disable-wslconfig) export UM_ENABLE_WSLCONFIG=0; shift ;;
    --wsl-networking) export UM_WSL_NETWORKING="$2"; shift 2 ;;
    *) INSTALL_ARGS+=("$1"); shift ;;
  esac
done

# UM_IS_WSL=1|0 overrides the detection (used by container tests).
is_wsl() {
  case "${UM_IS_WSL:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  grep -qi microsoft /proc/version 2>/dev/null
}
is_arch() { grep -qi '^ID=arch' /etc/os-release 2>/dev/null; }

if [ "$(id -u)" -eq 0 ]; then
  # A fresh Arch WSL starts as root with no user: stage 1, then a restart (ADR 0022).
  if is_arch && is_wsl; then
    if [ ! -f "$SCRIPT_DIR/install/stage1.sh" ]; then
      print_error "Run install.sh, not a piped bootstrap.sh: stage 1 needs the whole bootstrapper."
      exit 1
    fi
    exec bash "$SCRIPT_DIR/install/stage1.sh" --run
  fi
  print_error "Do not run this script as root. Clone and run as your regular user."
  exit 1
fi

print_info "Starting Umbra bootstrap..."

# WSL: get off the Windows filesystem before doing anything else
if is_wsl; then
  case "$PWD" in
    /mnt/*)
      print_info "Running from a Windows NTFS mount ($PWD); moving to \$HOME."
      cd "$HOME"
      ;;
  esac
  case "$UM_ENV_DIR" in
    /mnt/*)
      print_warning "UM_ENV_DIR ($UM_ENV_DIR) is on a Windows NTFS mount."
      print_warning "WSL2 cross-OS I/O is 10-20x slower; install under ~/ instead (e.g. UM_REPO_DIR=\$HOME/dev/umbra-bootstrapper)."
      ;;
  esac
fi

profile_given="${UM_MODE:-}"

# Ensure git is present (install minimal if not)
if ! command -v git >/dev/null 2>&1; then
  print_info "git not found. Attempting to install git..."
  if [ ! -f "$UM_ENV_DIR/install/common.sh" ]; then
    print_error "git is missing and the bootstrapper is not here; use install.sh."
    exit 1
  fi
  # shellcheck disable=SC1091
  source "$UM_ENV_DIR/install/common.sh"
  if command -v apt-get >/dev/null 2>&1; then
    run_priv apt-get update && run_priv apt-get install -y git
  elif command -v pacman >/dev/null 2>&1; then
    run_priv pacman -S --noconfirm --needed git
  else
    print_error "No supported package manager found to install git. Aborting."
    exit 1
  fi
fi

# Clone or update repo (UM_ENV_DIR is env/wsl inside the bootstrapper repo; inside the
# umbrella the bootstrapper is a submodule, whose .git is a file)
if [ -e "$UM_ENV_DIR/../../.git" ]; then
  print_info "Found existing bootstrapper repo at $UM_ENV_DIR/../.. — pulling updates..."
  (cd "$UM_ENV_DIR/../.." && git pull --rebase --autostash) || true
elif [ -d "$UM_ENV_DIR" ] && [ "$(ls -A "$UM_ENV_DIR" 2>/dev/null | wc -l)" -gt 0 ]; then
  print_warning "$UM_ENV_DIR exists and is not empty; using it without cloning."
else
  print_info "Cloning the bootstrapper into $UM_REPO_DIR (branch: $UM_BRANCH)..."
  git clone --depth=1 --branch "$UM_BRANCH" "$UM_REPO" "$UM_REPO_DIR"
  UM_ENV_DIR="$UM_REPO_DIR/env/wsl"
fi

# Export UM_ENV_DIR for child scripts
export UM_ENV_DIR
cd "$UM_ENV_DIR"
REPO_ROOT="$(cd "$UM_ENV_DIR/../.." && pwd)"

# If piped from curl, take the terminal back for the prompts below and chezmoi's.
# With --yes there are no prompts, so no terminal is needed (container tests).
if [ ! -t 0 ] && [ "${UM_NONINTERACTIVE:-0}" != "1" ]; then
  print_info "Detected piped execution, restoring terminal for interactive prompts..."
  exec </dev/tty
fi

# The choices install/run.sh used to ask (shell, theme, k8s) are asked here once;
# chezmoi stores them with the profile (ADR 0006, docs/plans/chezmoi.md §3-4).
# shellcheck disable=SC1091
source "$UM_ENV_DIR/install/common.sh"
if [ "$UM_VERBOSE" = "1" ]; then
  set -x
fi
if [ "$UM_NONINTERACTIVE" != "1" ] && is_tty; then
  select_shell
  select_theme
  if [ -z "${UM_ENABLE_K8S:-}" ]; then
    if confirm "Enable Kubernetes tooling (kubectl/helm/k3d)?" "y"; then
      UM_ENABLE_K8S=1
    else
      UM_ENABLE_K8S=0
    fi
  fi
else
  UM_ENABLE_K8S="${UM_ENABLE_K8S:-1}"
  select_shell
  select_theme
fi
export UM_ENABLE_K8S

# Profile: --profile/UM_MODE if given; otherwise chezmoi asks once (or personal without a terminal).
if [ -z "$profile_given" ]; then
  if [ "$UM_NONINTERACTIVE" = "1" ] || ! is_tty; then
    export UM_MODE=personal
  else
    unset UM_MODE
  fi
fi

bash "$UM_ENV_DIR/install/chezmoi.sh" --run

# chezmoi deploys the dotfiles and runs the install phases as scripts (env/.chezmoiscripts).
chezmoi_args=(init --apply --source "$REPO_ROOT")
if [ "$UM_NONINTERACTIVE" = "1" ]; then
  chezmoi_args+=(--no-tty --force)
fi
export UM_CHEZMOI_INIT=1
if ! chezmoi "${chezmoi_args[@]}"; then
  print_error "chezmoi stopped at the phase named above. Fix it, then run the same command again."
  exit 1
fi

# P6: only when stage 1 left a stage 2 pending (ADR 0022).
bash "$UM_ENV_DIR/install/finish.sh" --run
