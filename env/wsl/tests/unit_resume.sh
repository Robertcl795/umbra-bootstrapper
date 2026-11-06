#!/usr/bin/env bash
# unit_resume.sh — stage 2 through umbra-setup: `umbra bootstrap resume` in a terminal opens the
# user's verified umbra-setup on its run screen; without a terminal, with --plain, or without our
# binary it runs bootstrap.sh as before. Stage 1 copies its verified umbra-setup to the new user.
# No sudo, no network.
# shellcheck disable=SC2016,SC1091,SC2034
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
mkdir -p "$t/home/.local/state/um" "$t/home/.local/bin" "$t/env" "$t/bin"
printf 'export UM_ENV_DIR=%q\nexport UM_COMPONENTS=shell\n' "$t/env" >"$t/home/.local/state/um/bootstrap.env"
printf '#!/usr/bin/env bash\necho "plain $* comps=$UM_COMPONENTS"\n' >"$t/env/bootstrap.sh"
ours() {
  cat >"$t/home/.local/bin/umbra-setup" <<'S'
#!/usr/bin/env bash
[ "$1" = --version ] && { echo "umbra-setup 9.9.9 (Umbra bootstrapper)"; exit 0; }
echo "tui $* comps=$UM_COMPONENTS"
S
  chmod +x "$t/home/.local/bin/umbra-setup"
}

# resume [args...]: the wrapper without a terminal. tty_resume: inside script(1), a real pty.
resume() { env -i PATH=/usr/bin:/bin HOME="$t/home" bash "$ENV_DIR/bin/umbra" bootstrap resume 2>&1 </dev/null; }
tty_resume() {
  env -i PATH=/usr/bin:/bin HOME="$t/home" TERM=xterm script -qec "bash $ENV_DIR/bin/umbra bootstrap resume $*" /dev/null </dev/null 2>&1 | tr -d '\r'
}

echo "# umbra bootstrap resume"
ours
out="$(tty_resume)"
expect "a terminal and our umbra-setup: the TUI, resuming the staged env" '[[ $out == *"tui --resume --env-dir $t/env comps=shell"* ]]'
out="$(tty_resume --plain)"
expect "--plain: bootstrap.sh, as before" '[[ $out == *"plain  comps=shell"* || $out == *"plain comps=shell"* ]] && [[ $out != *tui* ]]'
out="$(resume)"
expect "no terminal: bootstrap.sh" '[[ $out == *"plain"* && $out != *tui* ]]'
printf '#!/bin/sh\necho someone else\n' >"$t/home/.local/bin/umbra-setup"
out="$(tty_resume)"
expect "an umbra-setup that is not ours: bootstrap.sh" '[[ $out == *"plain"* && $out != *"someone else"* ]]'
rm -f "$t/home/.local/bin/umbra-setup"
out="$(tty_resume)"
expect "no umbra-setup: bootstrap.sh" '[[ $out == *"plain"* ]]'

echo "# stage 1 hands its umbra-setup to the new user"
stage() {
  env -i PATH=/usr/bin:/bin HOME="$t/root" UM_ENV_DIR="$ENV_DIR" UM_USERNAME="$(id -un)" "$@" bash -c '
    source "$UM_ENV_DIR/install/stage1.sh"; stage_setup_bin "'"$t"'/home" "$(id -gn)"' 2>&1
}
ours
cp "$t/home/.local/bin/umbra-setup" "$t/bin/umbra-setup"
rm -f "$t/home/.local/bin/umbra-setup"
stage UM_SETUP_BIN="$t/bin/umbra-setup" >/dev/null
expect "copied to the user's ~/.local/bin, executable" '[ -x "$t/home/.local/bin/umbra-setup" ] && cmp -s "$t/bin/umbra-setup" "$t/home/.local/bin/umbra-setup"'
printf '#!/bin/sh\necho someone else\n' >"$t/home/.local/bin/umbra-setup"
out="$(stage UM_SETUP_BIN="$t/bin/umbra-setup")"
expect "a foreign umbra-setup there is kept" 'grep -q "someone else" "$t/home/.local/bin/umbra-setup" && [[ $out == *"not overwritten"* ]]'
rm -f "$t/home/.local/bin/umbra-setup"
printf '#!/bin/sh\necho fake\n' >"$t/bin/other"
chmod +x "$t/bin/other"
stage UM_SETUP_BIN="$t/bin/other" >/dev/null
expect "UM_SETUP_BIN that is not umbra-setup: nothing copied" '[ ! -e "$t/home/.local/bin/umbra-setup" ]'
stage >/dev/null
expect "no UM_SETUP_BIN (install.sh without the TUI): nothing copied, no error" '[ ! -e "$t/home/.local/bin/umbra-setup" ]'

echo "# finish.sh: the doctor never gets the terminal"
# zsh -lic in the doctor took the terminal's foreground from umbra-setup on a real Arch stage 2
# (2026-11-05: "read /dev/stdin: input/output error" after Done). The doctor must run without a
# controlling terminal.
mkdir -p "$t/fin/tests" "$t/fin/bin" "$t/fhome/.local/state/um"
: >"$t/fhome/.local/state/um/bootstrap.env"
printf '#!/usr/bin/env bash\nif { : </dev/tty; } 2>/dev/null; then echo doctor-has-tty; else echo doctor-no-tty; fi\n' >"$t/fin/tests/99_smoke.sh"
printf '#!/bin/sh\nexit 0\n' >"$t/fin/bin/sudo"
printf '#!/bin/sh\nexit 0\n' >"$t/fin/bin/chezmoi"
chmod +x "$t/fin/bin/sudo" "$t/fin/bin/chezmoi"
out="$(env -i PATH="$t/fin/bin:/usr/bin:/bin" HOME="$t/fhome" UM_ENV_DIR="$t/fin" TERM=xterm \
  script -qec "bash $ENV_DIR/install/finish.sh --run" /dev/null </dev/null 2>&1 | tr -d '\r')"
expect "in a terminal, the doctor still runs and has no controlling terminal" '[[ $out == *doctor-no-tty* && $out != *doctor-has-tty* ]]'
expect "the marker is removed after the doctor passed" '[ ! -e "$t/fhome/.local/state/um/bootstrap.env" ]'

echo "unit_resume: $pass ok, $fails failed"
[ "$fails" -eq 0 ]
