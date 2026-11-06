#!/usr/bin/env bash
# unit_setup_fetch.sh — install.sh's download of umbra-setup (ADR 0038): the pinned sha256 is
# required; cosign and gh checks run when the tool is there and stop the install when they fail;
# anything missing returns 1 (install.sh then stops and names the flags). A fake release is built from the real binary.
# Needs go. No sudo, no network (file:// downloads).
# shellcheck disable=SC2016,SC1091,SC2034
set -uo pipefail

TESTS="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd -- "$TESTS/.." && pwd)"
REPO="$(cd -- "$ENV_DIR/../.." && pwd)"
fails=0
pass=0
expect() {
  if eval "$2"; then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1"; fails=$((fails + 1)); fi
}

t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
ver=9.9.9
case "$(uname -m)" in aarch64 | arm64) arch=arm64 ;; *) arch=amd64 ;; esac
asset="umbra-setup_${ver}_linux_${arch}.tar.gz"
canon="https://github.com/Robertcl795/umbra-bootstrapper/releases/download/v$ver/$asset"

# The fake release: the archive as GoReleaser names it, checksums.txt and a bundle.
mkdir -p "$t/rel" "$t/env/install" "$t/bin" "$t/home"
(cd "$REPO" && CGO_ENABLED=0 go build -trimpath -ldflags "-X main.version=$ver" -o "$t/build/umbra-setup" ./cmd/umbra-setup) || { echo "go build failed"; exit 1; }
tar -czf "$t/rel/$asset" -C "$t/build" umbra-setup
sha="$(sha256sum "$t/rel/$asset" | cut -d' ' -f1)"
printf '%s  %s\n' "$sha" "$asset" >"$t/rel/checksums.txt"
: >"$t/rel/checksums.txt.sigstore.json"
printf '%s  %s\n' "$sha" "$canon" >"$t/env/install/checksums.sha256"

# The tools the tests may use: every command in /usr/bin and /bin except cosign and gh, so a
# cosign or gh installed on this machine never stands in for the fakes below (a real cosign
# rejects the fake release's bundle). The fakes go in $t/bin, first on PATH.
mkdir -p "$t/sys"
for f in /usr/bin/* /bin/*; do
  name="${f##*/}"
  case "$name" in cosign | gh) continue ;; esac
  [ -e "$t/sys/$name" ] || ln -s "$f" "$t/sys/$name"
done
TOOLS="$t/sys"

# fetch <env...>: runs fetch_setup in a clean shell; prints "path=<file>" or the messages.
fetch() {
  env -i PATH="$t/bin:$TOOLS" HOME="$t/home" UM_SETUP_DIR="$t/dl" UM_ENV_DIR="$t/env" \
    UM_SETUP_DOWNLOAD_BASE="file://$t/rel" "$@" bash -c '
    mkdir -p "$UM_SETUP_DIR"
    source "'"$ENV_DIR"'/install/common.sh"; UM_ENV_DIR="'"$t"'/env"
    source "'"$ENV_DIR"'/install/selector.sh"
    set +e; p="$(fetch_setup)"; rc=$?; [ "$rc" -eq 0 ] && echo "path=$p" || echo "rc=$rc"' 2>&1
}

echo "# pinning"
out="$(env -i PATH="$TOOLS" HOME="$t/home" bash -c 'source "'"$ENV_DIR"'/install/common.sh"; source "'"$ENV_DIR"'/install/selector.sh"; echo "$UM_SETUP_VERSION"')"
expect "the default pin is 0.5.0" '[ "$out" = 0.5.0 ]'
expect "both 0.5.0 archives have a sha256 line" '(for a in amd64 arm64; do grep -Eq "^[0-9a-f]{64}  https://github.com/Robertcl795/umbra-bootstrapper/releases/download/v0.5.0/umbra-setup_0.5.0_linux_$a.tar.gz\$" "$ENV_DIR/install/checksums.sha256" || exit 1; done)'
out="$(fetch UM_SETUP_VERSION=)"
expect "no pinned version: not available (1), said once" '[[ $out == *"no pinned release"* && $out == *rc=1* && $out != *gum* ]]'
out="$(fetch UM_SETUP_VERSION=1.0.0)"
expect "a version with no sha256 line: not available (1)" '[[ $out == *"No pinned sha256"* && $out == *rc=1* ]]'
out="$(fetch UM_SETUP_VERSION=$ver)"
expect "pinned and matching: the binary path" '[[ $out == *"path=$t/dl/setup/umbra-setup"* ]]'
expect "the fetched binary is the release" '[[ $("$t/dl/setup/umbra-setup" --version) == "umbra-setup $ver (Umbra bootstrapper)" ]]'
expect "without cosign and gh: both skips are said" '[[ $out == *"cosign not installed"* && $out == *"gh not logged in"* ]]'

cp "$t/rel/$asset" "$t/good.tgz"
printf 'x' >>"$t/rel/$asset"
out="$(fetch UM_SETUP_VERSION=$ver)"
expect "tampered archive: sha256 mismatch, stop (2)" '[[ $out == *"sha256 mismatch"* && $out == *rc=2* ]]'
cp "$t/good.tgz" "$t/rel/$asset"

echo "# cosign (when installed)"
cat >"$t/bin/cosign" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$t/cosign.args"
exit \${FAKE_COSIGN_RC:-0}
EOF
chmod +x "$t/bin/cosign"
out="$(fetch UM_SETUP_VERSION=$ver)"
expect "cosign ok: the path" '[[ $out == *path=* ]]'
expect "cosign verify-blob pins the release workflow at the tag and the GitHub issuer" \
  'grep -q -- "verify-blob --certificate-identity https://github.com/Robertcl795/umbra-bootstrapper/.github/workflows/release.yml@refs/tags/v$ver --certificate-oidc-issuer https://token.actions.githubusercontent.com --bundle" "$t/cosign.args"'
out="$(fetch UM_SETUP_VERSION=$ver FAKE_COSIGN_RC=1)"
expect "cosign fails: stop (2)" '[[ $out == *"signature check failed"* && $out == *rc=2* ]]'
printf '%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" "$asset" >"$t/rel/checksums.txt"
out="$(fetch UM_SETUP_VERSION=$ver)"
expect "signed checksums.txt disagrees with the pin: stop (2)" '[[ $out == *"checksums.txt does not list"* && $out == *rc=2* ]]'
printf '%s  %s\n' "$sha" "$asset" >"$t/rel/checksums.txt"
rm "$t/bin/cosign"

echo "# gh attestation (when logged in)"
cat >"$t/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "attestation --help") exit 0 ;;
  "attestation verify") printf '%s\n' "\$*" >"$t/gh.args"; exit \${FAKE_GH_RC:-0} ;;
esac
exit 1
EOF
chmod +x "$t/bin/gh"
out="$(fetch UM_SETUP_VERSION=$ver)"
expect "gh ok: the path, verified against the bootstrapper repo" '[[ $out == *path=* ]] && grep -q -- "-R Robertcl795/umbra-bootstrapper" "$t/gh.args"'
out="$(fetch UM_SETUP_VERSION=$ver FAKE_GH_RC=1)"
expect "attestation fails: stop (2)" '[[ $out == *"attestation check failed"* && $out == *rc=2* ]]'
rm "$t/bin/gh"

echo "# install into ~/.local/bin"
inst() {
  env -i PATH="$TOOLS" HOME="$t/home" bash -c '
    source "'"$ENV_DIR"'/install/common.sh"; source "'"$ENV_DIR"'/install/selector.sh"
    install_setup_bin "$1"' _ "$1" 2>&1
}
out="$(inst "$t/build/umbra-setup")"
expect "installed and its path printed" '[ "$out" = "$t/home/.local/bin/umbra-setup" ] && [ -x "$t/home/.local/bin/umbra-setup" ]'
printf '#!/bin/sh\necho someone else\n' >"$t/home/.local/bin/umbra-setup"
out="$(inst "$t/build/umbra-setup")"
expect "a foreign umbra-setup is kept; the verified copy runs from the temp dir" \
  '[[ $out == *"not overwritten"* ]] && [[ $(tail -n 1 <<<"$out") == "$t/build/umbra-setup" ]] && grep -q "someone else" "$t/home/.local/bin/umbra-setup"'

echo "unit_setup_fetch: $pass ok, $fails failed"
[ "$fails" -eq 0 ]
