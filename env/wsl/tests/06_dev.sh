#!/usr/bin/env bash
set -euo pipefail

if [ "${UM_ENABLE_K8S:-1}" = "0" ]; then
  echo "K8s tooling disabled; skipping." >&2
  exit 0
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not installed." >&2
  exit 1
fi
kubectl version --client >/dev/null

if ! command -v k3d >/dev/null 2>&1; then
  echo "k3d not installed." >&2
  exit 1
fi
k3d version >/dev/null
