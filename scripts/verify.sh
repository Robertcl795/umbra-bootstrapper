#!/usr/bin/env bash
# verify.sh — static checks of the bootstrapper (no containers). Prints PASS/FAIL per check;
# exits non-zero if any failed. The umbrella's scripts/verify.sh runs this too.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

failed=0

# report <name> <status> <output>: a failing check prints its reason on the last line of output.
report() {
  if (($2 == 0)); then
    echo "PASS $1"
  else
    echo "FAIL $1: $(tail -n 1 <<<"$3")"
    failed=$((failed + 1))
  fi
}

# env-syntax: the installer (env/wsl) and the chezmoi-managed zsh modules parse.
# No shellcheck here: migrated code is kept as-is (ADR 0009). Templates (*.tmpl) are
# checked by rendering them with chezmoi in the container tests.
check_env_syntax() {
  local f
  while IFS= read -r -d '' f; do
    bash -n "$f" || { echo "bash -n $f"; return 1; }
  done < <(find env/wsl -type f -name '*.sh' -print0)
  while IFS= read -r -d '' f; do
    zsh -n "$f" || { echo "zsh -n $f"; return 1; }
  done < <(find env/wsl env/dot_config -type f -name '*.zsh' -print0)
  bash -n scripts/verify.sh || { echo "bash -n scripts/verify.sh"; return 1; }
}

# layout: the repo root is a chezmoi source, and every `include "../themes/…"` resolves here.
check_layout() {
  [ "$(cat .chezmoiroot)" = env ] || { echo ".chezmoiroot does not point at env"; return 1; }
  local f inc
  while IFS=: read -r f inc; do
    inc=${inc#include \"../}
    inc=${inc%\"}
    [ -f "$inc" ] || { echo "$f includes missing $inc"; return 1; }
  done < <(grep -ro 'include "\.\./themes/[^"]*"' env)
}

# new-code: scripts added by the bootstrap fix pass shellcheck; migrated ones stay out of it
# (ADR 0023, 0009). guards: the rules of ADR 0021 and 0022 hold in the code.
check_new_code() {
  local f sc
  for f in env/wsl/install/stage1.sh env/wsl/install/stage1_pacman.sh env/wsl/install/stage1_apt.sh \
    env/wsl/install/finish.sh env/wsl/install/wsl_detect.sh \
    env/wsl/bin/umbra env/wsl/tests/unit_guards.sh env/wsl/tests/unit_phase.sh \
    env/wsl/tests/unit_wsl_detect.sh env/wsl/tests/unit_catalog.sh env/wsl/tests/unit_events.sh \
    env/wsl/tests/selector_dump.sh env/wsl/tests/unit_setup_fetch.sh env/wsl/tests/unit_resume.sh \
    env/wsl/install/terminal.sh env/wsl/tests/unit_terminal.sh env/wsl/tests/13_terminal.sh env/wsl/tests/14_pwsh.sh \
    env/wsl/tests/unit_packages.sh env/wsl/tests/01_packages.sh \
    test/pty/fakes/install.sh test/pty/fakes/doctor.sh test/pty/fakes/bin/sudo test/ps1/run.sh; do
    bash -n "$f" || { echo "bash -n $f"; return 1; }
    sc="$(shellcheck -f gcc "$f" 2>&1)" || { echo "$sc" >&2; echo "shellcheck: $(head -n 1 <<<"$sc")"; return 1; }
  done
}

check_guards() {
  bash env/wsl/tests/unit_guards.sh
  bash env/wsl/tests/unit_phase.sh
  bash env/wsl/tests/unit_wsl_detect.sh
  bash env/wsl/tests/unit_catalog.sh
  bash env/wsl/tests/unit_events.sh
  bash env/wsl/tests/unit_resume.sh
  bash env/wsl/tests/unit_terminal.sh
  bash env/wsl/tests/unit_packages.sh
}

# setup-fetch: install.sh's verified download of umbra-setup (ADR 0038); needs go for the fake release.
check_setup_fetch() {
  command -v go >/dev/null || { echo "go not installed"; return 1; }
  bash env/wsl/tests/unit_setup_fetch.sh
}

# go: umbra-setup (ADR 0037): gofmt, vet, tests (with the bash parity tests, contracts C1-C6) and
# the PTY flows of the built binary.
check_go() {
  command -v go >/dev/null || { echo "go not installed"; return 1; }
  local unformatted
  unformatted="$(gofmt -l cmd internal 2>/dev/null)"
  [ -z "$unformatted" ] || { echo "gofmt: $unformatted"; return 1; }
  go vet ./... >&2 || { echo "go vet failed"; return 1; }
  go test -count=1 ./... >&2 || { echo "go test failed (go test ./...)"; return 1; }
  go build -o build/umbra-setup ./cmd/umbra-setup || { echo "go build failed"; return 1; }
  local last
  last=$(python3 -I test/pty/test_setup.py 2>&1 | tail -n 1) || true
  [[ $last == *", 0 failed" ]] || { echo "pty ended with: $last"; return 1; }
}

# ps1: install.ps1 (ADR 0042) is ASCII (5.1 reads a BOM-less file as ANSI) and passes its Pester
# tests where powershell.exe is reachable (WSL); elsewhere the test runner prints skip.
check_ps1() {
  ! LC_ALL=C grep -nP '[^\x00-\x7F]' install.ps1 || { echo "install.ps1 is not ASCII"; return 1; }
  test/ps1/run.sh >&2 || { echo "Pester failed (test/ps1/run.sh)"; return 1; }
}

rc=0; out=$(check_env_syntax 2>&1) || rc=$?; report env-syntax "$rc" "$out"
rc=0; out=$(check_layout 2>&1) || rc=$?; report layout "$rc" "$out"
rc=0; out=$(check_new_code 2>&1) || rc=$?; report new-code "$rc" "$out"
rc=0; out=$(check_guards 2>&1) || rc=$?; report guards "$rc" "$out"
rc=0; out=$(check_setup_fetch 2>&1) || rc=$?; report setup-fetch "$rc" "$out"
rc=0; out=$(check_go 2>&1) || rc=$?; report go "$rc" "$out"
rc=0; out=$(check_ps1 2>&1) || rc=$?; report ps1 "$rc" "$out"

exit $((failed > 0))
