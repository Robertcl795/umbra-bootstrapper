#!/usr/bin/env bash
# unit_flags.sh — host-level checks of the bootstrapper switches added in the migration
# (--profile, --components/--skip, UM_IS_WSL). No packages, no network, no sudo.
set -uo pipefail

ENV_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
pass=0
check() {
  if eval "$2" >/dev/null 2>&1; then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1"; fails=$((fails + 1)); fi
}

# component_enabled <name> with the given UM_COMPONENTS / UM_SKIP.
enabled() {
  UM_COMPONENTS="$1" UM_SKIP="$2" bash -c 'source "$0/install/common.sh" && component_enabled "$1"' "$ENV_DIR" "$3"
}

echo "# components"
check "all phases enabled by default" 'enabled "" "" k8s'
check "--components limits to the list" 'enabled "link,prompt" "" prompt && ! enabled "link,prompt" "" k8s'
check "--skip removes a phase" '! enabled "" "k8s,lang" lang && enabled "" "k8s,lang" nvim'
check "names match whole words only" '! enabled "ai-standard" "" ai && enabled "" "ai" ai-cli'
check "--skip wins over --components" '! enabled "link" "link" link'

echo "# profile"
check "--profile rejects other values (exit 2)" '[ "$(bash "$ENV_DIR/bootstrap.sh" --profile other >/dev/null 2>&1; echo $?)" = 2 ]'
check "profile defaults to personal" '[ "$(env -u UM_MODE bash -c "source \"$ENV_DIR/install/common.sh\"; echo \$UM_MODE")" = personal ]'

echo "# UM_IS_WSL"
check "wsl.zsh active with UM_IS_WSL=1" 'UM_IS_WSL=1 zsh -c "source \"$ENV_DIR/../dot_config/zsh/wsl.zsh\"; alias explorer"'
check "wsl.zsh inert with UM_IS_WSL=0" '! UM_IS_WSL=0 zsh -c "source \"$ENV_DIR/../dot_config/zsh/wsl.zsh\"; alias explorer"'
check "00_preflight refuses non-WSL (UM_IS_WSL=0)" '! UM_IS_WSL=0 bash "$ENV_DIR/tests/00_preflight.sh"'
check "08_wsl skips outside WSL (UM_IS_WSL=0)" 'UM_IS_WSL=0 bash "$ENV_DIR/tests/08_wsl.sh"'

echo "unit_flags: $pass ok, $fails failed"
exit $((fails > 0))
