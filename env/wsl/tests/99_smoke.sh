#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"

for t in \
  "$SCRIPT_DIR/00_preflight.sh" \
  "$SCRIPT_DIR/01_packages.sh" \
  "$SCRIPT_DIR/02_linking.sh" \
  "$SCRIPT_DIR/03_shell.sh" \
  "$SCRIPT_DIR/04_prompt.sh" \
  "$SCRIPT_DIR/05_nvim.sh" \
  "$SCRIPT_DIR/06_dev.sh" \
  "$SCRIPT_DIR/07_devstack.sh" \
  "$SCRIPT_DIR/08_wsl.sh" \
  "$SCRIPT_DIR/09_ai.sh" \
  "$SCRIPT_DIR/12_fastfetch.sh"
do
  bash "$t"
done
