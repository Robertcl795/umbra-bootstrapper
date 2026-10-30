#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"

# common.sh sets its own SCRIPT_DIR.
TESTS_DIR="$SCRIPT_DIR"
export UM_ENV_DIR="${UM_ENV_DIR:-$(cd -- "$TESTS_DIR/.." && pwd)}"
# shellcheck disable=SC1091
source "$UM_ENV_DIR/install/common.sh"

# check <script> [component...]: runs it unless one of its components is not selected.
check() {
  local t="$1" c
  shift
  for c in "$@"; do
    component_enabled "$c" || return 0
  done
  bash "$TESTS_DIR/$t"
}

check 00_preflight.sh
check 01_packages.sh packages
check 02_linking.sh
check 03_shell.sh shell
check 04_prompt.sh prompt
check 05_nvim.sh nvim
check 06_dev.sh k8s
check 07_devstack.sh lang ai-cli
check 08_wsl.sh wsl
# umbra-ai is private (ADR 0018): a public install has no AI standard.
if find_ai_standard >/dev/null 2>&1; then
  check 09_ai.sh ai-standard
else
  echo "umbra-ai not present; skipping the AI standard check."
fi
check 12_fastfetch.sh fastfetch
