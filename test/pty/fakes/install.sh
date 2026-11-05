#!/usr/bin/env bash
# Fake install.sh for the PTY tests (UM_SETUP_INSTALL): records its arguments and runs two phases
# through the real helpers of common.sh, so the events are the ones bootstrap.sh would write.
# shellcheck disable=SC2016 # phase bodies are single-quoted on purpose: run_phase evaluates them
set -uo pipefail
printf '%s\n' "$*" >"$FAKE_ARGS"
[ "${GIT_TERMINAL_PROMPT:-}" = 0 ] || { echo "[fake] GIT_TERMINAL_PROMPT is not 0"; exit 9; }
[ ! -t 0 ] || { echo "[fake] stdin is a terminal"; exit 9; }
run_phase() { # run_phase <id> <body>
  (
    # shellcheck disable=SC1091
    source "$UM_ENV_DIR/install/common.sh"
    phase_start "$1"
    eval "$2"
  )
}
echo "[fake] starting"
run_phase run_onchange_before_20-shell.sh 'log_info "installing zsh"; sleep "${FAKE_SLEEP:-0.3}"; phase_gate shell "zsh is missing" test -z "${FAKE_FAIL:-}"' || exit $?
run_phase run_onchange_before_30-prompt.sh 'UM_SKIP=prompt; component_enabled prompt || phase_skip' || exit $?
echo "[fake] done"
