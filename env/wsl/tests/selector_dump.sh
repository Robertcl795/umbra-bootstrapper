#!/usr/bin/env bash
# selector_dump.sh — prints every selector output for every platform, for the golden of
# unit_catalog.sh (ADR 0039: reading components.tsv must not change a byte of it).
set -euo pipefail
ENV_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export UM_ENV_DIR="$ENV_DIR"
# shellcheck disable=SC1091
source "$ENV_DIR/install/common.sh"
# shellcheck disable=SC1091
source "$ENV_DIR/install/selector.sh"
unset DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
for p in wsl-ubuntu wsl-arch ubuntu arch omarchy; do
  echo "## $p items"
  selector_items "$p"
  for access in 0 1; do
    echo "## $p defaults access=$access"
    selector_defaults "$p" "$access"
    echo "## $p defaults access=$access desktop-session"
    (export XDG_CURRENT_DESKTOP=test; selector_defaults "$p" "$access")
  done
  ids="$(selector_items "$p" | cut -d'|' -f1 | paste -sd, -)"
  for sel in "$ids" "packages" "umbra-ai,shell,packages" "nvim,desktop,wsl,k8s" "typo,shell"; do
    echo "## $p items_to_components $sel"
    items_to_components "$p" "$sel" 2>&1
  done
done
