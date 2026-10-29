#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [ "$UM_VERBOSE" = "1" ]; then
  set -x
fi

if [ "$UM_NONINTERACTIVE" != "1" ] && is_tty; then
  select_shell
  select_theme
  if [ -z "${UM_ENABLE_K8S:-}" ]; then
    if confirm "Enable Kubernetes tooling (kubectl/helm/k3d)?" "y"; then
      UM_ENABLE_K8S=1
    else
      UM_ENABLE_K8S=0
    fi
  fi
else
  UM_ENABLE_K8S="${UM_ENABLE_K8S:-1}"
  select_shell
  select_theme
fi

export UM_ENABLE_K8S

source "$UM_ENV_DIR/install/detect_os.sh"
detect_os

log_info "Profile: $UM_MODE${UM_COMPONENTS:+ · components: $UM_COMPONENTS}${UM_SKIP:+ · skip: $UM_SKIP}"

# Phases run in the original order. Names for --components/--skip:
# packages link shell prompt nvim k8s zellij lang ai-cli wsl ai-standard fastfetch
if component_enabled packages; then
  case "$UM_OS" in
    ubuntu) bash "$UM_ENV_DIR/install/packages/ubuntu.sh" --run ;;
    arch) bash "$UM_ENV_DIR/install/packages/arch.sh" --run ;;
  esac
fi

component_enabled link && bash "$UM_ENV_DIR/install/link.sh" --run

if component_enabled shell; then
  # ADR 0004: fish is set up only when it is the chosen shell.
  if [ "$UM_SHELL" = "fish" ]; then
    bash "$UM_ENV_DIR/install/shell/fish.sh" --run
  fi
  bash "$UM_ENV_DIR/install/shell/zsh.sh" --run
fi

component_enabled prompt && bash "$UM_ENV_DIR/install/prompt/starship.sh" --run
component_enabled nvim && bash "$UM_ENV_DIR/install/nvim.sh" --run
component_enabled k8s && bash "$UM_ENV_DIR/install/dev/k8s.sh" --run
component_enabled zellij && bash "$UM_ENV_DIR/install/zellij.sh" --run
component_enabled lang && bash "$UM_ENV_DIR/install/dev/lang.sh" --run
component_enabled ai-cli && bash "$UM_ENV_DIR/install/dev/ai.sh" --run
component_enabled wsl && bash "$UM_ENV_DIR/install/wsl.sh" --run
# The AI standard is personal-only (ADR 0007, decision 11).
if [ "$UM_MODE" = "work" ]; then
  log_info "Work profile: skipping the AI standard (personal-only)."
elif component_enabled ai-standard; then
  bash "$UM_ENV_DIR/install/ai.sh" --run
fi
component_enabled fastfetch && bash "$UM_ENV_DIR/install/fastfetch.sh" --run

if [ -d "$UM_ENV_DIR/tests" ]; then
  chmod +x "$UM_ENV_DIR/tests/"*.sh 2>/dev/null || true
fi

log_step "Bootstrap complete."
bash "$UM_ENV_DIR/install/summary.sh" --run
log_info "Run tests with: tests/99_smoke.sh"
