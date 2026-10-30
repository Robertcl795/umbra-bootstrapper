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

rc=0; out=$(check_env_syntax 2>&1) || rc=$?; report env-syntax "$rc" "$out"
rc=0; out=$(check_layout 2>&1) || rc=$?; report layout "$rc" "$out"

exit $((failed > 0))
