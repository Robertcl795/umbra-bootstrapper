#!/usr/bin/env bash
# finish.sh — P6, the end of stage 2 (ADR 0021–0023): the doctor, then removal of everything stage 1
# left for the resume. Does nothing when no stage 2 is pending. If the doctor fails, the marker and
# the temporary sudo rule stay, so `umbra bootstrap resume` can retry.
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

UM_MARKER="$HOME/.local/state/um/bootstrap.env"

# no_tty <cmd...>: runs it in a new session, without a controlling terminal, and waits.
no_tty() {
  if command -v setsid >/dev/null 2>&1; then
    setsid -w "$@"
  else
    "$@"
  fi
}

finish_bootstrap() {
  [ -f "$UM_MARKER" ] || return 0
  # The doctor phase of umbra-setup's run screen (ADR 0040); it ends when this script exits.
  phase_start doctor
  log_step "P6: doctor and finish"

  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" UM_NO_FASTFETCH=1
  if ! chezmoi verify; then
    die "P6: chezmoi verify failed. Run 'chezmoi diff', then 'umbra bootstrap resume'."
  fi
  # The doctor runs zsh -lic, which takes the terminal's foreground when it can open it; under
  # umbra-setup that left the TUI in a background group (read: input/output error). setsid gives
  # it no controlling terminal; sudo still works through the temporary rule.
  if ! no_tty bash "$UM_ENV_DIR/tests/99_smoke.sh"; then
    die "P6: the doctor failed; the message above names the check. Fix it, then run 'umbra bootstrap resume'."
  fi

  run_priv rm -f /etc/profile.d/umbra-bootstrap.sh /usr/local/bin/umbra
  run_priv install -d -m 0755 /var/lib/umbra
  id -un | run_priv tee /var/lib/umbra/bootstrap-complete > /dev/null
  # Last privileged step: without this rule the calls above would need a password.
  run_priv rm -f /etc/sudoers.d/zz-umbra-bootstrap
  rm -f "$UM_MARKER"
  log_info "Bootstrap finished. Passwordless sudo is off."
}

if [ "${1:-}" = "--run" ]; then
  finish_bootstrap
fi
