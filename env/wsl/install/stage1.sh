#!/usr/bin/env bash
# stage1.sh — first boot of a root-only distro (ADR 0021–0023). Prepares the distro as root, then
# stops: /etc/wsl.conf applies only after a restart, so stage 2 runs later as the new user with
# `umbra bootstrap resume`. Every phase: postcondition already true → skip; otherwise precondition,
# apply, postcondition. Phases: docs/bootstrap-fix/fix-plan.md in the Umbra umbrella.
#
# Input: UM_USERNAME or a terminal prompt; UM_USER_PASSWORD_FILE or a terminal prompt, otherwise
# the account stays locked. UM_STAGE1_STOP_AFTER=<phase> stops after that phase, for tests.
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
UM_MODE_GIVEN="${UM_MODE:-}"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

BOOT_ROOT="$(cd -- "$UM_ENV_DIR/../.." && pwd)"
UM_BOOTSTRAPPER_REPO="${UM_BOOTSTRAPPER_REPO:-https://github.com/Robertcl795/umbra-bootstrapper.git}"
UM_BRANCH="${UM_BRANCH:-main}"
UM_COMPLETE_FILE=/var/lib/umbra/bootstrap-complete
UM_REMINDER=/etc/profile.d/umbra-bootstrap.sh
UM_COMMAND=/usr/local/bin/umbra
SUDOERS_WHEEL=/etc/sudoers.d/10-wheel
SUDOERS_TEMP=/etc/sudoers.d/zz-umbra-bootstrap
UM_USER="${UM_USERNAME:-}"

# phase <id> <precondition> <postcondition> <apply> <fix>: one phase of the contract (ADR 0023).
# apply runs under `||`, so errexit is off inside it: each step returns its own failure.
phase() {
  local id="$1" pre="$2" post="$3" apply="$4" fix="$5"
  log_step "$id"
  if "$post"; then
    log_info "$id: already satisfied."
  else
    "$pre" || die "$id: precondition failed. $fix"
    "$apply" || die "$id: apply failed. $fix"
    "$post" || die "$id: postcondition failed. $fix"
  fi
  if [ "${UM_STAGE1_STOP_AFTER:-}" = "$id" ]; then
    log_info "Stopping after $id (UM_STAGE1_STOP_AFTER)."
    exit 0
  fi
}

# --- P0 detect -------------------------------------------------------------------------------
p0_ok() {
  [ "$(id -u)" -eq 0 ] && grep -q '^ID=arch' /etc/os-release
}

# --- P1 root prerequisites -------------------------------------------------------------------
keyring_ready() {
  local keys
  keys="$(pacman-key --list-keys 2>/dev/null)" && [ -n "$keys" ]
}

p1_pre() {
  command -v pacman >/dev/null 2>&1
}

p1_post() {
  keyring_ready \
    && [ -n "$(ls -A /var/lib/pacman/sync 2>/dev/null)" ] \
    && pacman -Q base-devel git sudo >/dev/null 2>&1 \
    && [ -z "$(pacman -Qu 2>/dev/null)" ]
}

p1_apply() {
  # Only the image's first-launch script sets up the keyring; an imported distro has none.
  if ! keyring_ready; then
    pacman-key --init || return 1
    pacman-key --populate archlinux || return 1
  fi
  pacman -Syu --noconfirm --needed base-devel git sudo
}

# --- P2 user and wheel -----------------------------------------------------------------------
regular_users() {
  getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $1 }'
}

valid_username() {
  [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

# The user comes from --user/UM_USERNAME or a prompt. Existing users are never guessed.
p2_pre() {
  local existing
  existing="$(regular_users)"
  if [ -z "$UM_USER" ] && [ -n "$existing" ]; then
    log_error "This distro already has users: $(echo "$existing" | paste -sd' ' -). Name one with --user <name>."
    return 1
  fi
  if [ -z "$UM_USER" ] && is_tty; then
    read -r -p "Username for your new (sudo-enabled) user: " UM_USER
  fi
  if [ -z "$UM_USER" ]; then
    log_error "No username: pass --user <name> (or UM_USERNAME) when there is no terminal."
    return 1
  fi
  valid_username "$UM_USER" || { log_error "Invalid username: $UM_USER"; return 1; }
}

account_locked() {
  [ "$(passwd -S "$UM_USER" 2>/dev/null | awk '{ print $2 }')" = L ]
}

password_source() {
  [ -n "${UM_USER_PASSWORD_FILE:-}" ] || is_tty
}

# A password that can be set now and is not set yet keeps the phase open.
p2_post() {
  [ -n "$UM_USER" ] \
    && id -nG "$UM_USER" 2>/dev/null | tr ' ' '\n' | grep -qx wheel \
    && [ -f "$SUDOERS_WHEEL" ] && [ -f "$SUDOERS_TEMP" ] \
    && visudo -cf "$SUDOERS_WHEEL" >/dev/null 2>&1 \
    && visudo -cf "$SUDOERS_TEMP" >/dev/null 2>&1 \
    && runuser -u "$UM_USER" -- sudo -n true 2>/dev/null \
    && ! { account_locked && password_source; }
}

# install_sudoers <dest> <rule>: never edits /etc/sudoers; the file is checked before it is placed.
install_sudoers() {
  local dest="$1" rule="$2" tmp
  tmp="$(mktemp)"
  printf '%s\n' "$rule" > "$tmp"
  if ! visudo -cf "$tmp" >/dev/null; then
    rm -f "$tmp"
    log_error "Rejected by visudo: $rule"
    return 1
  fi
  install -m 0440 -o root -g root "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
}

set_password() {
  if [ -n "${UM_PASSWORD:-}" ]; then
    log_warn "UM_PASSWORD is ignored (ADR 0021): use UM_USER_PASSWORD_FILE or a terminal."
  fi
  if [ -n "${UM_USER_PASSWORD_FILE:-}" ]; then
    [ -r "$UM_USER_PASSWORD_FILE" ] || { log_error "Cannot read UM_USER_PASSWORD_FILE."; return 1; }
    { printf '%s:' "$UM_USER"; head -n 1 "$UM_USER_PASSWORD_FILE"; } | chpasswd || return 1
    log_info "Password set for $UM_USER from the password file."
  elif is_tty; then
    log_info "Set a password for $UM_USER (needed for sudo):"
    passwd "$UM_USER" || return 1
  else
    log_warn "No terminal and no UM_USER_PASSWORD_FILE: $UM_USER stays locked. Set a password with: wsl.exe -d ${WSL_DISTRO_NAME:-<distro>} -u root passwd $UM_USER"
  fi
}

p2_apply() {
  if id "$UM_USER" >/dev/null 2>&1; then
    log_info "User $UM_USER already exists; ensuring wheel membership."
    usermod -aG wheel "$UM_USER" || return 1
  else
    useradd -m -G wheel -s /bin/bash "$UM_USER" || return 1
  fi
  if account_locked; then
    set_password || return 1
  fi
  # /etc/sudoers.d/wheel from earlier versions sorts after numbered files and overrides them.
  if [ "$(cat /etc/sudoers.d/wheel 2>/dev/null)" = "%wheel ALL=(ALL) ALL" ]; then
    rm -f /etc/sudoers.d/wheel
  fi
  install_sudoers "$SUDOERS_WHEEL" "%wheel ALL=(ALL:ALL) ALL" || return 1
  # Removed when stage 2 finishes. zz sorts last, and in sudoers the last match wins.
  install_sudoers "$SUDOERS_TEMP" "$UM_USER ALL=(ALL:ALL) NOPASSWD: ALL"
}

# --- P3 wsl.conf -----------------------------------------------------------------------------
p3_pre() {
  id "$UM_USER" >/dev/null 2>&1
}

p3_post() {
  grep -qx 'systemd=true' /etc/wsl.conf 2>/dev/null && grep -qx "default=$UM_USER" /etc/wsl.conf
}

p3_apply() {
  wsl_conf_merge boot systemd true user default "$UM_USER"
}

# --- P3r stage point -------------------------------------------------------------------------
user_home() {
  getent passwd "$UM_USER" | cut -d: -f6
}

staged_repo() {
  echo "$(user_home)/dev/umbra-bootstrapper"
}

marker() {
  echo "$(user_home)/.local/state/um/bootstrap.env"
}

p3r_pre() {
  [ -f "$UM_ENV_DIR/bin/umbra" ] && [ -e "$BOOT_ROOT/.git" ]
}

p3r_post() {
  runuser -u "$UM_USER" -- git -C "$(staged_repo)" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && [ -f "$(marker)" ] && [ -x "$UM_COMMAND" ] && [ -f "$UM_REMINDER" ]
}

# git clone resolves the .git file of a submodule checkout, which a plain copy would leave dangling.
stage_repo() {
  local dest group cfg rc=0
  dest="$(staged_repo)"
  group="$(id -gn "$UM_USER")"
  if runuser -u "$UM_USER" -- git -C "$dest" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi
  if [ -e "$dest" ]; then
    mv "$dest" "$dest.backup.$(date +%Y%m%d_%H%M%S)" || return 1
  fi
  # A checkout owned by another uid needs safe.directory; a local clone ignores -c, not this file.
  cfg="$(mktemp)"
  git config -f "$cfg" safe.directory '*'
  GIT_CONFIG_GLOBAL="$cfg" git clone -q --no-hardlinks "$BOOT_ROOT" "$dest" || rc=$?
  rm -f "$cfg"
  [ "$rc" -eq 0 ] || return "$rc"
  git -C "$dest" remote set-url origin "$UM_BOOTSTRAPPER_REPO" || return 1
  chown -R "$UM_USER:$group" "$dest"
}

# The selection, for stage 2. Never a secret.
write_marker() {
  local tmp var group
  group="$(id -gn "$UM_USER")"
  tmp="$(mktemp)"
  {
    printf 'export UM_ENV_DIR=%q\n' "$(staged_repo)/env/wsl"
    printf 'export UM_BRANCH=%q\n' "$UM_BRANCH"
    if [ -n "$UM_MODE_GIVEN" ]; then
      printf 'export UM_MODE=%q\n' "$UM_MODE_GIVEN"
    fi
    for var in UM_SHELL UM_THEME UM_ENABLE_K8S UM_ENABLE_WSLCONFIG UM_WSL_NETWORKING UM_NONINTERACTIVE UM_COMPONENTS UM_SKIP; do
      if [ -n "${!var:-}" ]; then
        printf 'export %s=%q\n' "$var" "${!var}"
      fi
    done
  } > "$tmp"
  install -m 0600 -o "$UM_USER" -g "$group" "$tmp" "$(marker)" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
}

# The reminder only prints, to stderr so it never mixes into captured output. Nothing in a shell
# startup file starts stage 2 (ADR 0022).
install_reminder() {
  cat > "$UM_REMINDER" <<'EOF'
# Written by the Umbra bootstrapper; removed when stage 2 finishes.
case "$-" in
  *i*) [ -f "$HOME/.local/state/um/bootstrap.env" ] && echo "Umbra: run 'umbra bootstrap resume' to finish the install." >&2 ;;
esac
EOF
  chmod 0644 "$UM_REMINDER"
}

p3r_apply() {
  local home group
  home="$(user_home)"
  group="$(id -gn "$UM_USER")"
  install -d -o "$UM_USER" -g "$group" "$home/dev" "$home/.local" "$home/.local/state" "$home/.local/state/um" || return 1
  stage_repo || return 1
  write_marker || return 1
  if [ -e "$UM_COMMAND" ] && ! grep -q umbra-bootstrap-command "$UM_COMMAND"; then
    log_error "$UM_COMMAND exists and is not ours (ADR 0005); not overwriting it."
    return 1
  fi
  install -m 0755 -o root -g root "$UM_ENV_DIR/bin/umbra" "$UM_COMMAND" || return 1
  install_reminder
}

# --- Runner ----------------------------------------------------------------------------------
print_next_steps() {
  local distro="${WSL_DISTRO_NAME:-<distro>}"
  log_step "Stage 1 complete. The distro must restart before stage 2."
  log_info "From PowerShell or cmd, run:"
  log_info "  wsl.exe --terminate $distro"
  log_info "  wsl.exe -d $distro"
  log_info "Then, in that shell, as $UM_USER:"
  log_info "  umbra bootstrap resume"
}

run_stage1() {
  if [ -f "$UM_COMPLETE_FILE" ]; then
    log_info "This distro is already bootstrapped for $(cat "$UM_COMPLETE_FILE"). Run the command as that user."
    exit 0
  fi
  cd /root
  phase P0 true p0_ok true "Stage 1 runs as root on Arch."
  phase P1 p1_pre p1_post p1_apply "Check the network and the pacman output above, then run the command again."
  p2_pre || die "P2: precondition failed."
  phase P2 true p2_post p2_apply "See the message above, then run the command again."
  phase P3 p3_pre p3_post p3_apply "Check /etc/wsl.conf, then run the command again."
  phase P3r p3r_pre p3r_post p3r_apply "The repo could not be staged; see the message above, then run the command again."
  print_next_steps
}

if [ "${1:-}" = "--run" ]; then
  run_stage1
fi
