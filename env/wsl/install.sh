#!/usr/bin/env bash
set -euo pipefail

UM_ENV_DIR="${UM_ENV_DIR:-${UM_REPO_DIR:-$HOME/dev/umbra}/env/wsl}"
cd "$UM_ENV_DIR"

if [ -x "$UM_ENV_DIR/install/run.sh" ]; then
  exec "$UM_ENV_DIR/install/run.sh" "$@"
else
  echo "install/run.sh not found. Please update your umbra checkout." >&2
  exit 1
fi
