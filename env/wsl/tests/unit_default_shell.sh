#!/usr/bin/env bash
# unit_default_shell.sh — Make default (plan installer-packages-shell, T4): install/shell/default.sh
# sets the login shell and Windows Terminal's default profile, and only when asked; the run
# itself leaves the login shell alone when umbra-setup asks (UM_LOGIN_SHELL=keep). usermod, chsh,
# getent, /etc/shells and umbra-setup are fakes; nothing on this machine changes.
# shellcheck disable=SC1091,SC2016,SC2030,SC2031,SC2034,SC2317,SC2329 # the fakes are called by the sourced scripts
set -uo pipefail

TESTS="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd -- "$TESTS/.." && pwd)"
fails=0
pass=0
expect() {
  if (eval "$2"); then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1"; fails=$((fails + 1)); fi
}

t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
log="$t/calls"
mkdir -p "$t/bin" "$t/la"
for c in zsh fish; do printf '#!/bin/sh\n' >"$t/bin/$c"; done
printf '#!/usr/bin/env bash\necho "tester:x:1000:1000::/home/tester:${UM_FAKE_LOGIN:-/bin/bash}"\n' >"$t/bin/getent"
printf '#!/usr/bin/env bash\necho "chsh $*" >>%q\n' "$log" >"$t/bin/chsh"
printf '#!/usr/bin/env bash\n[ "$1" = -un ] && { echo tester; exit 0; }\nexec /usr/bin/id "$@"\n' >"$t/bin/id"
printf '#!/usr/bin/env bash\necho "umbra-setup $*" >>%q\ncase "$1" in\n  --wt-status) printf "default={04d0c07a-b717-5790-a033-fbd379a82afb}\\npwsh7=%%s\\n" "${UM_FAKE_PWSH7-{574e775e-4f2a-5b96-ac1e-a2962a402336\\}}" ;;\n  --wt-default-pwsh7) echo "backup=$2.umbra-x.bak" ;;\nesac\n' "$log" >"$t/bin/umbra-setup"
chmod +x "$t/bin"/*
: >"$t/la/settings.json"
export PATH="$t/bin:/usr/bin:/bin" USER=someone-else UM_SHELLS_FILE="$t/shells" UM_SETUP_BIN="$t/bin/umbra-setup"
export UM_WIN_LOCALAPPDATA_U="$t/la" UM_WIN_LOCALAPPDATA_W='C:\Users\t\AppData\Local' UM_WIN_SETTINGS="$t/la/settings.json"
printf '/bin/sh\n/bin/bash\n' >"$UM_SHELLS_FILE"

# in_scripts <cmd...>: the functions of default.sh with run_priv logged instead of run.
in_scripts() {
  (
    source "$ENV_DIR/install/shell/default.sh"
    set +e
    run_priv() { echo "priv $*" >>"$log"; if [ "$1" = tee ]; then cat >>"${*: -1}"; fi; }
    log_step() { :; }
    log_info() { echo "$*"; }
    log_warn() { echo "$*"; }
    "$@"
  )
}

echo "# login shell"
: >"$log"
out="$(in_scripts default_status)"
expect "--status names the login shell and Windows Terminal's default and PowerShell 7 profiles" \
  'grep -qx "login=/bin/bash" <<<"$out" && grep -qx "wt_default={04d0c07a-b717-5790-a033-fbd379a82afb}" <<<"$out" && grep -qx "wt_pwsh7={574e775e-4f2a-5b96-ac1e-a2962a402336}" <<<"$out"'
: >"$log"
in_scripts default_shell_set fish >/dev/null
expect "fish: added to /etc/shells, then usermod -s for the user" \
  'grep -qx "$t/bin/fish" "$UM_SHELLS_FILE" && grep -qx "priv usermod -s $t/bin/fish tester" "$log"'
: >"$log"
in_scripts default_shell_set fish >/dev/null
expect "a second time: /etc/shells is not appended again" '[ "$(grep -c "^$t/bin/fish$" "$UM_SHELLS_FILE")" = 1 ]'
: >"$log"
UM_FAKE_LOGIN="$t/bin/zsh" in_scripts default_shell_set zsh >/dev/null
expect "already the login shell: nothing runs" '! grep -q "usermod\|chsh" "$log"'
expect "an unknown shell is refused" '! in_scripts default_shell_set tcsh >/dev/null'
: >"$log"
expect "Omarchy keeps its login shell (ADR 0011)" '! UM_OS=omarchy in_scripts default_shell_set zsh >/dev/null && ! grep -q usermod "$log"'

echo "# Windows Terminal: PowerShell 7 as the default profile"
: >"$log"
out="$(in_scripts default_wt_pwsh7)"
expect "umbra-setup changes defaultProfile of the settings.json found (a backup first)" \
  'grep -qx "umbra-setup --wt-default-pwsh7 $t/la/settings.json" "$log" && grep -q "umbra-x.bak" <<<"$out"'
: >"$log"
UM_FAKE_PWSH7="" in_scripts default_wt_pwsh7 >/dev/null
expect "no PowerShell 7 profile yet: nothing is written" '! grep -q "wt-default-pwsh7" "$log"'

echo "# the run leaves the login shell to Make default"
: >"$log"
(
  source "$ENV_DIR/install/shell/zsh.sh"
  run_priv() { echo "priv $*" >>"$log"; }
  log_info() { :; }
  UM_SHELL=zsh UM_NONINTERACTIVE=1 UM_LOGIN_SHELL=keep set_default_shell_zsh
) >/dev/null 2>&1
expect "zsh.sh with --yes and UM_LOGIN_SHELL=keep does not change the login shell" '! grep -q "usermod\|chsh" "$log"'
: >"$log"
(
  source "$ENV_DIR/install/shell/zsh.sh"
  run_priv() { echo "priv $*" >>"$log"; }
  log_info() { :; }
  grep() { [ "$1" = -qx ] && return 0; command grep "$@"; }
  UM_SHELL=zsh UM_NONINTERACTIVE=1 set_default_shell_zsh
) >/dev/null 2>&1
expect "without it (bootstrap.sh --yes on its own) zsh.sh still sets zsh, as before" 'grep -q "priv usermod -s" "$log"'
expect "the doctor does not ask for a zsh login shell when Make default decides" \
  'grep -q "UM_LOGIN_SHELL" "$TESTS/03_shell.sh"'

echo "unit_default_shell: $pass ok, $fails failed"
[ "$fails" -eq 0 ]
