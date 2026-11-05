#!/usr/bin/env bash
# unit_catalog.sh — the component catalog (ADR 0039): its rows are valid, and the selector that
# reads it prints byte for byte what the hard-coded selector printed (golden/selector.txt).
# No packages, no sudo, no network.
set -uo pipefail

TESTS="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd -- "$TESTS/.." && pwd)"
REPO="$(cd -- "$ENV_DIR/../.." && pwd)"
CATALOG="$ENV_DIR/install/components.tsv"
fails=0
pass=0
ok() { echo "  ok   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

echo "# golden"
if bash "$TESTS/selector_dump.sh" | diff -q "$TESTS/golden/selector.txt" - >/dev/null; then
  ok "selector output matches golden/selector.txt"
else
  bad "selector output differs from golden/selector.txt"
fi

t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
sed 's/\tNeovim\t/\tNeovim editor\t/' "$CATALOG" >"$t/changed.tsv"
if UM_CATALOG="$t/changed.tsv" bash "$TESTS/selector_dump.sh" | diff -q "$TESTS/golden/selector.txt" - >/dev/null; then
  bad "a changed label is caught by the golden"
else
  ok "a changed label is caught by the golden"
fi

echo "# rows"
n=0 seen=","
problems=()
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  case "$line" in '' | '#'*) continue ;; esac
  IFS=$'\t' read -r -a f <<<"$line"
  if [ "${f[0]}" = id ]; then
    [ "${#f[@]}" -eq 13 ] || problems+=("line $n: header has ${#f[@]} columns, want 13")
    continue
  fi
  [ "${#f[@]}" -eq 13 ] || { problems+=("line $n: ${#f[@]} columns, want 13"); continue; }
  id="${f[0]}" plats="${f[1]}" def="${f[3]}" work="${f[12]}"
  [[ $id =~ ^[a-z][a-z0-9-]*$ ]] || problems+=("line $n: bad id '$id'")
  [[ $seen == *",$id/$plats,"* ]] && problems+=("line $n: duplicate $id for $plats")
  seen+="$id/$plats,"
  [[ $plats =~ ^(all|!?[a-z-]+(,[a-z-]+)*)$ ]] || problems+=("line $n: bad platforms '$plats'")
  case "$def" in yes | no | desktop-session | ai-access) ;; *) problems+=("line $n: bad default '$def'") ;; esac
  case "$work" in same | limited | off) ;; *) problems+=("line $n: bad work '$work'") ;; esac
  for i in 4 5 6 7; do
    [ -n "${f[$i]}" ] && [ "${f[$i]}" != - ] || problems+=("line $n: column $((i + 1)) is empty")
  done
  for i in 4 5; do
    [[ ${f[$i]} == *[,=]* ]] && problems+=("line $n: label holds ',' or '='")
  done
  IFS=, read -r -a scripts <<<"${f[10]}"
  for s in "${scripts[@]}"; do
    [ -f "$REPO/env/.chezmoiscripts/$s.tmpl" ] || problems+=("line $n: no script $s")
  done
  [ "${f[11]}" = - ] || [ -f "$TESTS/${f[11]}" ] || problems+=("line $n: no check ${f[11]}")
done <"$CATALOG"
head -n 1 "$CATALOG" | grep -q '^# schema 1 ' || problems+=("line 1: no '# schema 1' comment")
if [ "${#problems[@]}" -eq 0 ]; then
  ok "every row is valid (schema 1)"
else
  bad "invalid rows: ${problems[*]}"
fi

echo "unit_catalog: $pass ok, $fails failed"
[ "$fails" -eq 0 ]
