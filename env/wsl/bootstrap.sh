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

# ---------------------------------------------------------------------------
# Arch WSL first boot: a fresh archlinux WSL instance starts as root with no
# regular user. Provision the system, create a sudo-enabled user and set it
# as the WSL default, then ask for a restart before the real bootstrap runs.
# A one-shot hook in the new user's ~/.bashrc resumes the bootstrap
# automatically on the first login after 'wsl --shutdown'.
# ---------------------------------------------------------------------------

# Ask for a password twice (hidden input) and set it via chpasswd.
# UM_PASSWORD skips the prompt for non-interactive setups.
set_user_password() {
  local username="$1" pass="" confirm=""
  if [ -n "${UM_PASSWORD:-}" ]; then
    if printf '%s:%s\n' "$username" "$UM_PASSWORD" | chpasswd; then
      print_success "Password set for $username (from UM_PASSWORD)."
    else
      print_warning "Password not set; run 'passwd $username' manually."
    fi
    return 0
  fi
  if [ ! -e /dev/tty ]; then
    print_warning "No terminal available; set a password later with 'passwd $username'."
    return 0
  fi
  print_info "Set a password for $username (needed for sudo):"
  while :; do
    read -r -s -p "  Password: " pass </dev/tty; echo >&2
    if [ -z "$pass" ]; then
      print_warning "Password cannot be empty; try again."
      continue
    fi
    read -r -s -p "  Confirm password: " confirm </dev/tty; echo >&2
    if [ "$pass" != "$confirm" ]; then
      print_warning "Passwords do not match; try again."
      continue
    fi
    break
  done
  if printf '%s:%s\n' "$username" "$pass" | chpasswd; then
    print_success "Password set for $username."
  else
    print_warning "Password not set; run 'passwd $username' manually."
  fi
  pass=""; confirm=""
}

arch_first_boot() {
  print_info "Fresh Arch WSL detected (running as root). Starting first-boot provisioning..."

  # Move out of the Windows filesystem (9P mounts are 10-20x slower)
  case "$PWD" in
    /mnt/*) print_info "Leaving Windows filesystem (cd /root)..."; cd /root ;;
  esac

  print_info "Updating system (pacman -Syu)..."
  pacman -Syu --noconfirm
  pacman -S --noconfirm --needed sudo git

  print_info "Granting sudo to the wheel group..."
  echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
  chmod 440 /etc/sudoers.d/wheel

  local username="${UM_USERNAME:-}"
  if [ -z "$username" ] && [ -e /dev/tty ]; then
    read -r -p "Username for your new (sudo-enabled) user: " username </dev/tty
  fi
  if [ -z "$username" ]; then
    print_error "No username provided. Re-run with UM_USERNAME=<name> for non-interactive setups."
    exit 1
  fi

  if id "$username" >/dev/null 2>&1; then
    print_info "User $username already exists; ensuring wheel membership."
    usermod -aG wheel "$username"
  else
    useradd -m -G wheel -s /bin/bash "$username"
    set_user_password "$username"
  fi

  # Boot into this user (and systemd) by default from now on
  if [ -f /etc/wsl.conf ]; then
    cp /etc/wsl.conf "/etc/wsl.conf.backup.$(date +%Y%m%d_%H%M%S)"
  fi
  cat > /etc/wsl.conf << EOF
[boot]
systemd=true

[user]
default=$username
EOF

  # -------------------------------------------------------------------------
  # Stage the repo and a one-shot resume hook so the bootstrap continues
  # automatically the first time $username logs in after the restart.
  # -------------------------------------------------------------------------
  local user_home staged
  user_home="$(getent passwd "$username" | cut -d: -f6)"
  user_home="${user_home:-/home/$username}"
  staged="$user_home/dev/umbra-bootstrapper"

  if [ ! -d "$staged" ]; then
    mkdir -p "$user_home/dev"
    if [ -d "$SCRIPT_DIR/.git" ] || [ -d "$SCRIPT_DIR/install" ]; then
      print_info "Staging the bootstrapper at $staged..."
      cp -a "$SCRIPT_DIR/../.." "$staged"
    else
      print_info "Cloning the bootstrapper into $staged (branch: $UM_BRANCH)..."
      git clone --depth=1 --branch "$UM_BRANCH" "$UM_REPO" "$staged" \
        || print_warning "Clone failed; the resume hook will fetch the bootstrap itself."
    fi
  fi

  local var val
  {
    printf 'export UM_ENV_DIR=%q\n' "$staged/env/wsl"
    printf 'export UM_BRANCH=%q\n' "$UM_BRANCH"
    for var in UM_SHELL UM_THEME UM_ENABLE_K8S UM_ENABLE_WSLCONFIG UM_WSL_NETWORKING UM_NONINTERACTIVE UM_VERBOSE UM_MODE UM_COMPONENTS UM_SKIP; do
      val="$(printenv "$var" 2>/dev/null || true)"
      if [ -n "$val" ]; then
        printf 'export %s=%q\n' "$var" "$val"
      fi
    done
  } > "$user_home/.umbra-resume.env"

  touch "$user_home/.bashrc"
  if ! grep -q "umbra-bootstrap-resume" "$user_home/.bashrc"; then
    cat >> "$user_home/.bashrc" << 'RESUME_HOOK'

# >>> umbra-bootstrap-resume >>>
# One-shot hook written by bootstrap.sh first-boot provisioning.
# It removes itself after running once.
if [ -f "$HOME/.umbra-resume.env" ] && [ -t 0 ]; then
  . "$HOME/.umbra-resume.env"
  rm -f "$HOME/.umbra-resume.env"
  sed -i '/^# >>> umbra-bootstrap-resume >>>$/,/^# <<< umbra-bootstrap-resume <<<$/d' "$HOME/.bashrc"
  echo "Resuming Umbra bootstrap..."
  if [ -f "${UM_ENV_DIR:-$HOME/dev/umbra-bootstrapper/env/wsl}/bootstrap.sh" ]; then
    bash "${UM_ENV_DIR:-$HOME/dev/umbra-bootstrapper/env/wsl}/bootstrap.sh"
  else
    curl -fsSL "https://raw.githubusercontent.com/Robertcl795/umbra-bootstrapper/${UM_BRANCH:-main}/env/wsl/bootstrap.sh" | bash
  fi
fi
# <<< umbra-bootstrap-resume <<<
RESUME_HOOK
  fi
  chown "$username:" "$user_home/dev" 2>/dev/null || true
  chown -R "$username:" "$staged" 2>/dev/null || true
  chown "$username:" "$user_home/.bashrc" "$user_home/.umbra-resume.env"

  print_success "First-boot provisioning complete."
  print_info "WSL must now restart. When you reopen Arch it will log in as $username"
  print_info "and the bootstrap will continue automatically."

  local wsl_exe=""
  if command -v wsl.exe >/dev/null 2>&1; then
    wsl_exe="wsl.exe"
  elif [ -x /mnt/c/Windows/System32/wsl.exe ]; then
    wsl_exe="/mnt/c/Windows/System32/wsl.exe"
  fi

  if [ -n "$wsl_exe" ] && [ -e /dev/tty ] && [ "${UM_NONINTERACTIVE:-0}" != "1" ]; then
    local reply=""
    read -r -p "Shut down WSL now? (Y/n) " reply </dev/tty
    case "$reply" in
      [Nn]*)
        print_info "Skipped. Run 'wsl --shutdown' from PowerShell when ready, then reopen Arch."
        ;;
      *)
        print_info "Shutting down WSL (this window will close)..."
        exec "$wsl_exe" --shutdown
        ;;
    esac
  else
    print_info "Now restart WSL from PowerShell:   wsl --shutdown"
    print_info "Then reopen Arch to continue the installation."
  fi
  exit 0
}

if [ "$(id -u)" -eq 0 ]; then
  if is_arch && is_wsl; then
    arch_first_boot
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

# Ensure git is present (install minimal if not)
if ! command -v git >/dev/null 2>&1; then
  print_info "git not found. Attempting to install git..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y git
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm git
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
profile_given="${UM_MODE:-}"
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
exec chezmoi "${chezmoi_args[@]}"
