#!/usr/bin/env bash
# unit_phase.sh — the phase runner of stage1.sh (ADR 0023): a failing phase prints its message,
# exits non-zero, and the next phase does not run. No packages, no root.
# shellcheck disable=SC2016,SC2034,SC2317,SC2329
set -uo pipefail

ENV_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ENV_DIR/install/stage1.sh"
set +e
fails=0

expect() {
  if ! eval "$2"; then
    echo "FAIL $1"
    fails=$((fails + 1))
  fi
}

ok() { return 0; }
no() { return 1; }

# run_two <post> <apply>: one phase, then a phase that writes a file if reached.
run_two() (
  next="$1"
  phase PX ok "$2" "$3" "the fix text" 2>&1
  : >"$next"
)

t="$(mktemp -d)"

out="$(run_two "$t/a" no no)"; rc=$?
expect "failing apply exits non-zero" '[ "$rc" -ne 0 ]'
expect "failing apply prints the fix" '[[ $out == *"PX: apply failed. the fix text"* ]]'
expect "failing apply stops the run" '[ ! -e "$t/a" ]'

out="$(run_two "$t/b" no ok)"; rc=$?
expect "postcondition is checked after apply" '[ "$rc" -ne 0 ] && [[ $out == *"PX: postcondition failed"* ]] && [ ! -e "$t/b" ]'

applied="$t/applied"
mark() { : >"$applied"; }
out="$(run_two "$t/c" ok mark)"; rc=$?
expect "satisfied phase skips apply" '[ "$rc" -eq 0 ] && [ ! -e "$applied" ] && [ -e "$t/c" ]'

pre_run() (
  phase PX no no ok "the fix text" 2>&1
)
out="$(pre_run)"; rc=$?
expect "failing precondition stops before apply" '[ "$rc" -ne 0 ] && [[ $out == *"PX: precondition failed"* ]]'

# Events (ADR 0040, setup-tui G4): each stage 1 phase starts and ends in the stream.
ev="$t/events"
: >"$ev"
(UM_EVENTS="$ev" phase PA ok ok ok "fix" 2>/dev/null; UM_EVENTS="$ev" phase PB ok no ok "fix" 2>/dev/null; UM_EVENTS="$ev" phase PC ok ok ok "fix" 2>/dev/null)
expect "events: PA start ok, PB start then fail on exit, PC never starts" \
  '[ "$(awk -F"\t" "\$3 == \"phase\" { print \$4 \"/\" \$5 }" "$ev" | paste -sd, -)" = "PA/start,PA/ok,PB/start,PB/fail" ]'

rm -rf "$t"
exit $((fails > 0))
