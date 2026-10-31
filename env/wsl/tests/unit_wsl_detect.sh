#!/usr/bin/env bash
# unit_wsl_detect.sh — wsl_detect.sh against a fake wsl.exe and fake /proc. No root, no real WSL:
# PATH drops the Windows directories, and the fake wsl.conf moves the drive mount away from /mnt.
# shellcheck disable=SC2016,SC2034,SC2317,SC2329
set -uo pipefail

ENV_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ENV_DIR/install/wsl_detect.sh"
fails=0

t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
bin="$t/bin"
mkdir -p "$bin" "$t/proc/1" "$t/drive"
PATH="$bin:/usr/bin:/bin"
export WSL_DISTRO_NAME=fake UM_WSL_TIMEOUT=2
export UM_WSL_CONF="$t/wsl.conf" UM_WSL_PROC="$t/proc" UM_WSL_UNAME=6.18.54.1-microsoft-standard-WSL2

expect() {
  if ! eval "$2"; then
    echo "FAIL $1"
    fails=$((fails + 1))
  fi
}

# report <key>: the value detection printed.
value() { wsl_detect_report | awk -F= -v k="$1" '$1 == k { print substr($0, length(k) + 2) }'; }

# fake_wsl <exit code> <bytes file>: --version prints the file; -d prints the default user.
fake_wsl() {
  cat >"$bin/wsl.exe" <<EOF
#!/usr/bin/env bash
: >"$t/wsl-called"
if [ "\$1" = -d ]; then echo "\${FAKE_DEFAULT_USER:-root}"; exit 0; fi
cat "$2"
exit $1
EOF
  chmod +x "$bin/wsl.exe"
}

fake_wslinfo() {
  cat >"$bin/wslinfo" <<EOF
#!/usr/bin/env bash
case "\$1" in
  --version) echo "${1:-}" ;;
  --networking-mode) echo "${2:-}" ;;
esac
EOF
  chmod +x "$bin/wslinfo"
}

no_wsl() { rm -f "$bin/wsl.exe"; }

utf16() { iconv -f UTF-8 -t UTF-16LE; }

reset_machine() {
  rm -f "$t/wsl-called" "$bin/wslc.exe"
  printf 'Linux version 6.18.54.1-microsoft-standard-WSL2\n' >"$t/proc/version"
  printf 'bash\n' >"$t/proc/1/comm"
  printf 'rootfs / ext4 rw 0 0\nC:\\ %s/c 9p rw,aname=drvfs 0 0\n' "$t/drive" >"$t/proc/mounts"
  printf '[automount]\nroot=%s/drive\n' "$t" >"$t/wsl.conf"
  unset FAKE_DEFAULT_USER
  fake_wslinfo "" ""
}

# The bytes of the real command: UTF-16LE, CRLF, no BOM.
printf 'WSL version: 3.0.3.0\r\nKernel version: 6.18.54.1-1\r\nWSLg version: 1.0.79\r\nMSRDC version: 1.2.7391\r\nWindows version: 10.0.26200.9711\r\n' \
  | utf16 >"$t/en.bin"
{
  printf '\377\376'
  printf 'Versi\303\263n de WSL: 2.4.4.0\r\nVersi\303\263n de kernel: 5.15.167.4-1\r\nVersi\303\263n de WSLg: 1.0.65\r\n' | utf16
} >"$t/es.bin"
printf 'WSL version: 3.1.0.0\nKernel version: 7.0.1.1-2\n' >"$t/utf8.bin"
printf 'Invalid command line argument: --version\r\n' | utf16 >"$t/old.bin"

reset_machine
fake_wsl 0 "$t/en.bin"
wsl_detect
expect "UTF-16 version" '[ "$(value version)" = 3.0.3.0 ] && [ "$(value version_source)" = wsl.exe ]'
expect "major version" '[ "$(value major)" = 3 ]'
expect "UTF-16 kernel" '[ "$(value kernel_reported)" = 6.18.54.1-1 ]'
expect "uname kernel" '[ "$(value kernel)" = "$UM_WSL_UNAME" ]'
expect "VM from the kernel name" '[ "$(value vm)" = 2 ]'
expect "wsl.exe ran, so interop works" '[ "$(value interop)" = yes ]'
expect "systemd not PID 1" '[ "$(value systemd_pid1)" = no ]'
expect "Windows files on 9p" '[ "$(value windows_fs)" = 9p ]'
expect "no wslc" '[ "$(value wslc)" = no ]'
expect "no wslinfo answer" '[ "$(value networking)" = unknown ]'
expect "report is key=value only" '! wsl_detect_report | grep -qv "^[a-z_0-9]*="'
# Left in, the NUL bytes reach $(...), and bash warns about them on every run.
expect "UTF-16 leaves no noise on stderr" '[ -z "$(wsl_detect 2>&1 >/dev/null)" ]'

reset_machine
fake_wsl 0 "$t/es.bin"
wsl_detect
expect "translated labels and a BOM" '[ "$(value version)" = 2.4.4.0 ] && [ "$(value kernel_reported)" = 5.15.167.4-1 ] && [ "$(value major)" = 2 ]'

reset_machine
fake_wsl 0 "$t/utf8.bin"
wsl_detect
expect "plain UTF-8 output" '[ "$(value version)" = 3.1.0.0 ] && [ "$(value kernel_reported)" = 7.0.1.1-2 ]'

# An older wsl.exe rejects --version: interop still works, the version comes from wslinfo or nowhere.
reset_machine
fake_wsl 255 "$t/old.bin"
wsl_detect
expect "rejected --version: version unknown" '[ "$(value version)" = unknown ] && [ "$(value version_source)" = none ] && [ "$(value major)" = unknown ]'
expect "rejected --version: interop works" '[ "$(value interop)" = yes ]'

reset_machine
no_wsl
fake_wslinfo 3.0.3.0 nat
wsl_detect
expect "no wsl.exe: wslinfo fills in" '[ "$(value version)" = 3.0.3.0 ] && [ "$(value version_source)" = wslinfo ] && [ "$(value networking)" = nat ]'
expect "no wsl.exe: no interop" '[ "$(value interop)" = no ]'
expect "no wsl.exe: rest degrades" '[ "$(value kernel_reported)" = unknown ] && [ "$(value conf_user)" = unset ]'

reset_machine
no_wsl
wsl_detect
expect "nothing to ask: unknown, not a failure" '[ "$(value version)" = unknown ] && [ "$(value major)" = unknown ]'

reset_machine
fake_wsl 126 "$t/en.bin"
wsl_detect
expect "interop disabled" '[ "$(value interop)" = no ] && [ "$(value version)" = unknown ]'

reset_machine
cat >"$bin/wsl.exe" <<'EOF'
#!/usr/bin/env bash
exec sleep 30
EOF
chmod +x "$bin/wsl.exe"
UM_WSL_TIMEOUT=1
start=$SECONDS
wsl_detect
expect "a hung wsl.exe times out" '[ $((SECONDS - start)) -lt 10 ] && [ "$(value interop)" = no ]'
UM_WSL_TIMEOUT=2

# wsl.conf against the live state.
reset_machine
fake_wsl 0 "$t/en.bin"
printf '[boot]\r\n# systemd=false\nsystemd = "true"\n[user]\ndefault=umbra\n[interop]\nenabled=true\n[automount]\nroot=%s/drive\noptions="metadata,umask=22"\n' "$t" >"$t/wsl.conf"
wsl_detect
expect "keys written, not restarted" '[ "$(value conf_systemd)" = pending ] && [ "$(value conf_user)" = pending ] && [ "$(value conf_automount)" = pending ]'
expect "interop key honored" '[ "$(value conf_interop)" = honored ]'
printf 'systemd\n' >"$t/proc/1/comm"
printf 'C:\\ %s/c 9p rw,metadata,aname=drvfs 0 0\n' "$t/drive" >"$t/proc/mounts"
export FAKE_DEFAULT_USER=umbra
wsl_detect
expect "keys honored after a restart" '[ "$(value conf_systemd)" = honored ] && [ "$(value conf_user)" = honored ] && [ "$(value conf_automount)" = honored ]'
expect "systemd PID 1" '[ "$(value systemd_pid1)" = yes ]'

reset_machine
fake_wsl 0 "$t/en.bin"
wsl_detect
expect "no keys: unset" '[ "$(value conf_systemd)" = unset ] && [ "$(value conf_user)" = unset ] && [ "$(value conf_automount)" = unset ]'

# virtiofs does not report drvfs options, so they are never called pending.
reset_machine
printf 'C:\\ %s/c virtiofs rw 0 0\n' "$t/drive" >"$t/proc/mounts"
printf '[automount]\nroot=%s/drive\noptions="metadata"\n' "$t" >"$t/wsl.conf"
wsl_detect
expect "virtiofs named, options unknown" '[ "$(value windows_fs)" = virtiofs ] && [ "$(value conf_automount)" = unknown ]'

reset_machine
printf '#!/bin/sh\n' >"$bin/wslc.exe"
chmod +x "$bin/wslc.exe"
wsl_detect
expect "wslc on PATH" '[ "$(value wslc)" = yes ]'

reset_machine
UM_WSL_UNAME=4.4.0-22621-Microsoft
wsl_detect
expect "WSL 1 kernel" '[ "$(value vm)" = 1 ]'
UM_WSL_UNAME=6.18.54.1-microsoft-standard-WSL2

reset_machine
fake_wsl 0 "$t/en.bin"
printf 'Linux version 6.8.0 (buildd@ubuntu)\n' >"$t/proc/version"
wsl_detect
expect "native Linux: no wsl.exe call" '[ "$(value wsl)" = 0 ] && [ ! -e "$t/wsl-called" ]'
reset_machine
fake_wsl 0 "$t/en.bin"
UM_IS_WSL=0 wsl_detect
expect "UM_IS_WSL=0 wins" '[ "$(value wsl)" = 0 ] && [ ! -e "$t/wsl-called" ]'

# Runs clean under the callers' options.
reset_machine
no_wsl
expect "safe under set -eu" '(set -euo pipefail; wsl_detect; [ "$UM_DET_WSL" = 1 ])'
expect "sourcing ignores the callers arguments" '[ -z "$(bash -c "source \"$ENV_DIR/install/wsl_detect.sh\"" _ --report)" ]'
expect "direct run reports" 'bash "$ENV_DIR/install/wsl_detect.sh" --report | grep -q "^wsl=1$"'

# wsl.sh: drvfs options only where they are known to apply.
merge_args() (
  # shellcheck disable=SC1091
  source "$ENV_DIR/install/wsl.sh"
  set +e
  wsl_conf_merge() { echo "$*"; }
  UM_DET_WINDOWS_FS="$1" configure_wsl_conf 2>/dev/null
)
expect "wsl.sh writes the drvfs options on 9p" '[[ $(merge_args 9p) == *"automount options"* ]]'
expect "wsl.sh leaves them alone on virtiofs" '[[ $(merge_args virtiofs) != *"automount options"* ]] && [[ $(merge_args virtiofs) == *"boot systemd true"* ]]'

exit $((fails > 0))
