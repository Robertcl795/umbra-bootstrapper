#!/usr/bin/env bash
# unit_events.sh — the phase event stream (ADR 0040): with UM_EVENTS set, the phase helpers append
# v1 TSV events; without it, their output is byte-identical to before. No packages, no root.
# shellcheck disable=SC2016,SC2034
set -uo pipefail

ENV_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
pass=0
expect() {
  if eval "$2"; then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1"; fails=$((fails + 1)); fi
}

t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
TAB=$'\t'
ESC=$'\033'

# run <events file or empty> <commands>: a fresh shell with common.sh; prints stderr.
run() {
  local ev="$1"
  shift
  env -u UM_EVENTS -u UM_PHASE TAB="$TAB" ${ev:+UM_EVENTS="$ev"} bash -c "source '$ENV_DIR/install/common.sh'; set +e; $*" 2>&1
}

echo "# without UM_EVENTS"
out="$(run "" 'log_info hello; log_warn careful; log_error broken; phase_gate prompt "the fix" true; phase_gate prompt "the fix" false')"
want="${ESC}[0;34m[INFO]${ESC}[0m hello
${ESC}[1;33m[WARN]${ESC}[0m careful
${ESC}[0;31m[ERROR]${ESC}[0m broken
${ESC}[0;34m[INFO]${ESC}[0m gate prompt: ok
${ESC}[0;31m[ERROR]${ESC}[0m gate prompt failed: the fix"
expect "log and gate output unchanged" '[ "$out" = "$want" ]'
out="$(run "" 'phase_start run_onchange_before_30-prompt.sh')"
expect "phase_start prints nothing" '[ -z "$out" ]'

echo "# with UM_EVENTS"
ev="$t/events"
: >"$ev"
run "$ev" 'phase_start run_onchange_before_30-prompt.sh; log_info "installing${TAB}starship"; phase_gate prompt "starship missing" true' >/dev/null
mapfile -t lines <"$ev"
expect "three events" '[ "${#lines[@]}" -eq 3 ]'
IFS="$TAB" read -r v ts kind phase state msg <<<"${lines[0]:-}"
expect "start event" '[ "$v" = v1 ] && [ "$kind" = phase ] && [ "$phase" = run_onchange_before_30-prompt.sh ] && [ "$state" = start ]'
expect "timestamp is UTC RFC 3339 with milliseconds" '[[ $ts =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$ ]]'
expect "log event tagged with the current phase, tab replaced" '[ "$(cut -f3- <<<"${lines[1]:-}")" = "log${TAB}run_onchange_before_30-prompt.sh${TAB}info${TAB}installing starship" ]'
expect "gate ok event for the current phase" '[ "$(cut -f3- <<<"${lines[2]:-}")" = "phase${TAB}run_onchange_before_30-prompt.sh${TAB}ok${TAB}gate prompt" ]'

: >"$ev"
run "$ev" 'phase_gate nvim "nvim does not start" false' >/dev/null
expect "failed gate without phase_start uses the gate id" '[ "$(cut -f3- "$ev")" = "phase${TAB}nvim${TAB}fail${TAB}nvim does not start" ]'

: >"$ev"
run "$ev" 'log_warn "two
lines"' >/dev/null
expect "newline replaced, phase '-' when none" '[ "$(cut -f3- "$ev")" = "log${TAB}-${TAB}warn${TAB}two lines" ]'

: >"$ev"
run "$ev" "log_error \"\$(printf 'x%.0s' {1..600})\"" >/dev/null
expect "message cut to 512 bytes" '[ "$(cut -f6 "$ev" | tr -d "\n" | wc -c)" -eq 512 ]'

out="$(run "$t/missing-dir/events" 'log_info still works; phase_gate prompt fix true; echo rc=$?')"
expect "unwritable UM_EVENTS is ignored" '[[ $out == *"still works"* && $out == *"rc=0"* ]] && [ ! -e "$t/missing-dir/events" ]'

echo "unit_events: $pass ok, $fails failed"
[ "$fails" -eq 0 ]
