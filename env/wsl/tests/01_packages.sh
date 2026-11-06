#!/usr/bin/env bash
# 01_packages.sh — every package row of install/packages.tsv for this OS that has a command is on
# PATH (a|b: either one), except the rows left out with --skip-packages.
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
TESTS_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
export UM_ENV_DIR="${UM_ENV_DIR:-$(cd -- "$TESTS_DIR/.." && pwd)}"
if [ -z "${UM_OS:-}" ] && [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  UM_OS="$(. /etc/os-release && echo "${ID:-}")"
fi
export UM_OS
# shellcheck disable=SC1091
source "$UM_ENV_DIR/install/common.sh"

rows="$(pkg_rows packages)" # set -e: a missing table fails the check
missing=0
while IFS=$'\t' read -r name _ cmds; do
  [ "$cmds" != "-" ] || continue
  found=0
  IFS='|' read -ra alts <<<"$cmds"
  for c in "${alts[@]}"; do
    if command -v "$c" >/dev/null 2>&1; then found=1; break; fi
  done
  if [ "$found" = 0 ]; then
    echo "Missing $name (${cmds//|/ or })." >&2
    missing=1
  fi
done <<<"$rows"
exit "$missing"
