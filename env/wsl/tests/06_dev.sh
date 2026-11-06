#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UM_ENV_DIR="${UM_ENV_DIR:-$(cd -- "$TESTS_DIR/.." && pwd)}"
# shellcheck disable=SC1091
source "$UM_ENV_DIR/install/common.sh"

if [ "${UM_ENABLE_K8S:-1}" = "0" ]; then
  echo "K8s tooling disabled; skipping." >&2
  exit 0
fi

# The rows left out with --skip-packages are not checked.
if pkg_wanted k8s kubectl; then
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not installed." >&2
    exit 1
  fi
  kubectl version --client >/dev/null
fi

if pkg_wanted k8s k3d; then
  if ! command -v k3d >/dev/null 2>&1; then
    echo "k3d not installed." >&2
    exit 1
  fi
  k3d version >/dev/null
fi
