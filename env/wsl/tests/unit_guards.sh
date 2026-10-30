#!/usr/bin/env bash
# unit_guards.sh — rules of ADR 0021 and 0022 that must keep holding in the code. Static.
#   no sudo: only run_priv calls sudo; a direct call fails a fresh distro with no sudo.
#   no --shutdown: it stops every distro on the machine, not just this one.
set -uo pipefail

ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT" || exit 1
fails=0

# Code only: tests and docs may name these words.
code_files() {
  find install.sh env/wsl/bootstrap.sh env/wsl/install.sh env/wsl/install env/wsl/bin env/.chezmoiscripts env/.chezmoitemplates -type f
}

# sudo in command position, outside comments. Probing (`sudo -n true`, `-v`) changes nothing, and
# run_priv itself runs `sudo "$@"` and `sudo -n "$@"`.
direct_sudo() {
  code_files | xargs grep -nE '(^|[;&|(!]|\b(then|do|else|if|while))[[:space:]]*sudo[[:space:]]' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | grep -vE 'sudo -n true|sudo (-n )?"\$@"'
}

found="$(direct_sudo)"
if [ -n "$found" ]; then
  echo "direct sudo: $(head -n 1 <<<"$found")"
  fails=$((fails + 1))
fi

found="$(code_files | xargs grep -n -e '--shutdown' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')"
if [ -n "$found" ]; then
  echo "--shutdown in code: $(head -n 1 <<<"$found")"
  fails=$((fails + 1))
fi

exit $((fails > 0))
