#!/usr/bin/env bash
# unit_install.sh — host-level checks of install.sh (the single command, ADR 0016-0018):
# platform detection, selector defaults and the item → --components mapping, via --dry-run.
# No packages, no sudo; network only if UM_AI_ACCESS is unset (it is set in every check).
set -uo pipefail

ENV_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ENV_DIR/../../install.sh"
fails=0
pass=0
check() {
  if eval "$2" >/dev/null 2>&1; then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1"; fails=$((fails + 1)); fi
}

# dry <env assignments...> -- <install.sh args...>: the --dry-run line, without a desktop session.
dry() {
  local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  env -u DISPLAY -u WAYLAND_DISPLAY -u XDG_CURRENT_DESKTOP -u UM_MODE -u UM_SELECT -u UM_SKIP \
    UM_AI_ACCESS=1 "${envs[@]}" bash "$INSTALL" --dry-run "$@" 2>/dev/null | tail -n 1
}
ALL="packages,shell,prompt,nvim,k8s,zellij,lang,fastfetch"
AI="ai-cli,ai-standard,um,vault,ollama"

echo "# platform"
check "UM_OS=ubuntu UM_IS_WSL=1 → wsl-ubuntu" '[[ $(dry UM_OS=ubuntu UM_IS_WSL=1 -- --yes) == "platform=wsl-ubuntu "* ]]'
check "UM_OS=arch UM_IS_WSL=0 → arch (native)" '[[ $(dry UM_OS=arch UM_IS_WSL=0 -- --yes) == "platform=arch "* ]]'
check "UM_OS=omarchy → omarchy" '[[ $(dry UM_OS=omarchy UM_IS_WSL=0 -- --yes) == "platform=omarchy "* ]]'
check "unsupported OS stops with exit 1" '! env UM_OS=fedora UM_AI_ACCESS=1 bash "$INSTALL" --dry-run --yes'

echo "# defaults (--yes)"
check "WSL: all phases, WSL tuning, Umbra AI; no desktop" '[[ $(dry UM_OS=ubuntu UM_IS_WSL=1 -- --yes) == *" components=$ALL,wsl,$AI "* ]]'
check "native without a desktop session: no desktop, no WSL tuning" '[[ $(dry UM_OS=arch UM_IS_WSL=0 -- --yes) == *" components=$ALL,$AI "* ]]'
check "native with a desktop session: desktop pieces added" '[[ $(dry UM_OS=ubuntu UM_IS_WSL=0 XDG_CURRENT_DESKTOP=GNOME -- --yes) == *" components=$ALL,desktop,$AI "* ]]'
check "Omarchy: tools, shell, prompt, Umbra AI only (ADR 0011)" '[[ $(dry UM_OS=omarchy UM_IS_WSL=0 -- --yes) == *" components=packages,shell,prompt,$AI "* ]]'
check "WSL with a desktop session: still no desktop pieces" '[[ $(dry UM_OS=arch UM_IS_WSL=1 DISPLAY=:0 -- --yes) != *desktop* ]]'
check "work profile keeps the same items (limits are in the phases)" '[[ $(dry UM_OS=ubuntu UM_IS_WSL=1 -- --yes --profile work) == *" profile=work components=$ALL,wsl,$AI "* ]]'

echo "# Umbra AI access (ADR 0018)"
check "no access: Umbra AI left out of the defaults" '[[ $(dry UM_OS=ubuntu UM_IS_WSL=0 UM_AI_ACCESS=0 -- --yes) == *" components=$ALL skip= ai_access=0" ]]'
check "no access: selecting it prints the reason and drops it" 'out=$(env UM_OS=ubuntu UM_IS_WSL=0 UM_AI_ACCESS=0 UM_SELECT=packages,umbra-ai bash "$INSTALL" --dry-run 2>&1) && [[ $out == *"Umbra AI is private"* && $out == *" components=packages skip="* ]]'

echo "# UM_SELECT and flags"
check "UM_SELECT maps items to components in menu order" '[[ $(dry UM_OS=ubuntu UM_IS_WSL=0 UM_SELECT=umbra-ai,shell,packages --) == *" components=packages,shell,$AI "* ]]'
check "UM_SELECT drops items the platform does not offer" '[[ $(dry UM_OS=omarchy UM_IS_WSL=0 UM_SELECT=packages,nvim,desktop --) == *" components=packages skip="* ]]'
check "--components passes through unchanged (no selector)" '[[ $(dry UM_OS=ubuntu UM_IS_WSL=1 -- --components shell,k8s --skip k8s) == *" components=shell,k8s skip=k8s "* ]]'
check "--profile rejects other values" '! env UM_OS=ubuntu UM_AI_ACCESS=1 bash "$INSTALL" --dry-run --profile other'
check "nothing selected stops" '! env UM_OS=ubuntu UM_IS_WSL=0 UM_AI_ACCESS=1 UM_SELECT=nvim-typo bash "$INSTALL" --dry-run'

echo "# opt-in components (plain bootstrap.sh unchanged)"
enabled() {
  UM_COMPONENTS="$1" UM_SKIP="" bash -c 'source "$0/install/common.sh" && component_enabled "$1"' "$ENV_DIR" "$2"
}
check "desktop, um, vault, ollama off without --components" '! enabled "" desktop && ! enabled "" um && ! enabled "" vault && ! enabled "" ollama'
check "opt-in components on when listed" 'enabled "desktop,um" desktop && enabled "desktop,um" um && ! enabled "desktop,um" ollama'
check "gum and the new downloads are pinned" 'for u in gum_2.0.2_Linux_x86_64.tar.gz gum_2.0.2_Linux_arm64.tar.gz JetBrainsMono.tar.xz ollama-linux-amd64.tar.zst ollama-linux-arm64.tar.zst; do grep -Eq "^[0-9a-f]{64}  https://github.com/.*/$u\$" "$ENV_DIR/install/checksums.sha256" || exit 1; done'

echo "unit_install: $pass ok, $fails failed"
exit $((fails > 0))
