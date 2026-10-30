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

finish_bootstrap() {
  [ -f "$UM_MARKER" ] || return 0
  log_step "P6: doctor and finish"

  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" UM_NO_FASTFETCH=1
  if ! chezmoi verify; then
    die "P6: chezmoi verify failed. Run 'chezmoi diff', then 'umbra bootstrap resume'."
  fi
  if ! bash "$UM_ENV_DIR/tests/99_smoke.sh"; then
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
