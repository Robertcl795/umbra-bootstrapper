#!/usr/bin/env bash
# unit_packages.sh — install/packages.tsv is the one package list (plan installer-packages-shell, T1):
# the package scripts install exactly its rows for UM_OS, minus UM_SKIP_PACKAGES (only rows with
# skip=yes), and the doctor checks the same rows. The package managers, the release downloads and
# the network are fakes; nothing is installed.
# shellcheck disable=SC1090,SC1091,SC2013,SC2016,SC2030,SC2031,SC2034,SC2317,SC2329 # the fakes are called by the sourced scripts
set -uo pipefail

TESTS="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd -- "$TESTS/.." && pwd)"
TSV="$ENV_DIR/install/packages.tsv"
fails=0
pass=0
expect() {
  if (eval "$2"); then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1"; fails=$((fails + 1)); fi
}

t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
log="$t/calls"

# rows <os> <component> <source...>: the manager names the TSV lists, read here on its own (the
# test does not use the helpers it checks).
rows() {
  local os="$1" comp="$2"
  shift 2
  awk -F'\t' -v os="$os" -v comp="$comp" -v srcs=" $* " '
    /^#/ || $1 == "name" { next }
    $2 != comp || index(srcs, " " $4 " ") == 0 { next }
    { ok = 0
      if ($3 == "all") ok = 1
      else if (substr($3, 1, 1) == "!") ok = (substr($3, 2) != os)
      else { n = split($3, l, ","); for (i = 1; i <= n; i++) if (l[i] == os) ok = 1 } }
    ok { print ($5 == "-" ? $1 : $5) }' "$TSV" | sort
}

# run_install <os> <function> <script>: the script's install function with the fakes; the calls go to $log.
run_install() {
  : >"$log"
  (
    export UM_OS="$1" UM_ENV_DIR="$ENV_DIR" UM_SHELL=zsh HOME="$t/home"
    mkdir -p "$HOME"
    source "$ENV_DIR/install/$3"
    set +e
    run_priv() { echo "priv $*" >>"$log"; }
    ensure_cmd() { return 1; }
    install_release_bin() { echo "release $1" >>"$log"; }
    pinned_sha256() { echo 0; }
    curl() { echo "curl $*" >>"$log"; }
    git() { echo "git $*" >>"$log"; }
    log_step() { :; }
    log_info() { :; }
    log_warn() { :; }
    "$2"
  ) >/dev/null 2>&1
}

# batch <manager words>: the packages of the first install call of that manager, sorted.
batch() { local l; l="$(grep -m1 "^priv $1 " "$log")"; tr ' ' '\n' <<<"${l#"priv $1 "}" | sort; }

echo "# the table"
expect "every row has 9 fields and both descriptions" \
  '! awk -F"\t" '"'"'!/^#/ && (NF != 9 || $8 == "" || $9 == "") { bad = 1 } END { exit !bad }'"'"' "$TSV"'
expect "every component exists in components.tsv" \
  'comm -23 <(awk -F"\t" '"'"'!/^#/ && $1 != "name" { print $2 }'"'"' "$TSV" | sort -u) <(awk -F"\t" '"'"'!/^#/ && $1 != "id" { print $1 }'"'"' "$ENV_DIR/install/components.tsv" | sort -u) | grep -q . && exit 1 || exit 0'

echo "# ubuntu"
run_install ubuntu install_packages_ubuntu packages/ubuntu.sh
expect "apt installs exactly the pm rows" '[ "$(batch "apt-get install -y")" = "$(rows ubuntu packages pm)" ]'
expect "the pm-try rows go in their own batch, with duf (apt first, then a release)" 'grep -q "^priv apt-get install -y duf just lnav$" "$log"'
expect "fd is apt's fd-find" 'batch "apt-get install -y" | grep -qx fd-find'
expect "the code rows are installed: eza, tldr, starship, lazygit, sshs" \
  'grep -q "apt-get install -y eza" "$log" && grep -q "apt-get install -y tldr" "$log" && grep -q "starship.rs/install.sh" "$log" && grep -q "^release lazygit" "$log" && grep -q "^release sshs" "$log"'

export UM_SKIP_PACKAGES="fzf,eza,lazygit,just,git,zsh"
run_install ubuntu install_packages_ubuntu packages/ubuntu.sh
expect "a skipped pm row is left out" '! batch "apt-get install -y" | grep -qx fzf'
expect "a skipped code row is not installed" '! grep -q "eza" "$log" && ! grep -q "^release lazygit" "$log"'
expect "a skipped pm-try row is left out" 'grep -q "^priv apt-get install -y duf lnav$" "$log"'
expect "rows the component needs (skip=no) stay" 'batch "apt-get install -y" | grep -qx git && batch "apt-get install -y" | grep -qx zsh'
unset UM_SKIP_PACKAGES

echo "# arch"
run_install arch install_packages_arch packages/arch.sh
expect "pacman installs exactly the pm rows" '[ "$(batch "pacman -S --noconfirm --needed")" = "$(rows arch packages pm)" ]'
expect "sshs (code) is installed" 'grep -q "^release sshs" "$log" || grep -q "aur.archlinux.org/yay-bin" "$log"'
UM_SKIP_PACKAGES="sshs,yazi" run_install arch install_packages_arch packages/arch.sh
expect "skipped: sshs not fetched, yazi not in the batch" '! grep -q "sshs" "$log" && ! batch "pacman -S --noconfirm --needed" | grep -qx yazi'

echo "# omarchy"
run_install omarchy install_packages_omarchy packages/omarchy.sh
expect "pacman installs exactly the pm rows" '[ "$(batch "pacman -S --noconfirm --needed")" = "$(rows omarchy packages pm)" ]'
expect "no system update on Omarchy (ADR 0011)" '! grep -q "pacman -Sy" "$log"'

echo "# lang and k8s"
UM_SKIP_PACKAGES="uv,helm" run_install ubuntu install_lang_toolchains dev/lang.sh
expect "lang: a skipped uv is not installed, the rest are" '! grep -q "astral.sh/uv" "$log" && grep -q "sh.rustup.rs" "$log" && grep -q "fnm.vercel.app" "$log"'
UM_SKIP_PACKAGES="helm" run_install ubuntu install_k8s_tools dev/k8s.sh
expect "k8s: a skipped helm is not installed, k3d is" '! grep -q "get-helm-3" "$log" && grep -q "k3d-io/k3d" "$log"'

echo "# the doctor reads the same rows"
mkdir -p "$t/bin"
for c in $(awk -F'\t' '!/^#/ && $1 != "name" && $2 == "packages" && $6 != "-" { n = split($6, a, "|"); print a[1] }' "$TSV" | sort -u); do
  printf '#!/bin/sh\n' >"$t/bin/$c"
done
chmod +x "$t/bin"/*
# Only the fakes and the tools the check itself runs: this machine has its own fzf and git.
for c in awk grep sed tr cut dirname cat; do ln -s "$(command -v "$c")" "$t/bin/$c"; done
doctor() { (export UM_OS=arch UM_ENV_DIR="$ENV_DIR" PATH="$t/bin"; "$BASH" "$ENV_DIR/tests/01_packages.sh") >/dev/null 2>&1; }
expect "all commands present: the check passes" 'doctor'
rm "$t/bin/fzf"
expect "fzf missing: the check fails" '! doctor'
expect "fzf missing but skipped: the check passes" 'UM_SKIP_PACKAGES=fzf doctor'
rm "$t/bin/git"
expect "git missing: skipping it does not help (skip=no)" '! UM_SKIP_PACKAGES=fzf,git doctor'

echo "# the selection carries across the restart"
marker_has() {
  (
    source "$ENV_DIR/install/stage1.sh"
    user_home() { echo "$t/mhome"; }
    mkdir -p "$t/mhome/.local/state/um"
    UM_USER="$(id -un)" UM_BRANCH=main UM_MODE_GIVEN="" UM_SKIP_PACKAGES="fzf,uv" write_marker
  ) >/dev/null 2>&1 && [ "$(source "$t/mhome/.local/state/um/bootstrap.env" && echo "$UM_SKIP_PACKAGES")" = "fzf,uv" ]
}
expect "stage 1's marker for stage 2 keeps UM_SKIP_PACKAGES" 'marker_has'

echo "unit_packages: $pass passed, $fails failed"
[ "$fails" -eq 0 ]
