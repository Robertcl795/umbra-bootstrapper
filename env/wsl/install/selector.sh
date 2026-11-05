#!/usr/bin/env bash
# selector.sh — platform detection and the component selector of install.sh
# (ADR 0016, docs/plans/platform.md §3-4 in the Umbra umbrella). Sourced after common.sh.

UM_GUM_VERSION="2.0.2"
# umbra-setup (ADR 0038): the release install.sh fetches. Empty until the operator publishes one;
# then set it here and add the asset's sha256 to checksums.sha256. Empty means the gum menu.
UM_SETUP_VERSION="${UM_SETUP_VERSION:-}"
UM_SETUP_REPO_URL="https://github.com/Robertcl795/umbra-bootstrapper"
UM_AI_PRIVATE_MSG="Umbra AI is private: log in with \`gh auth login\` or add an SSH key with access, then run the command again."

# um_platform: wsl-ubuntu, wsl-arch, ubuntu, arch or omarchy. UM_OS (ubuntu|arch|omarchy) and
# UM_IS_WSL (0|1) override the detection, for tests. Anything else returns 1.
um_platform() {
  local id="${UM_OS:-}" wsl
  if [ -z "$id" ] && [ -f /etc/os-release ]; then
    id="$(. /etc/os-release && echo "${ID:-}")"
  fi
  case "${UM_IS_WSL:-}" in
    1) wsl=1 ;;
    0) wsl=0 ;;
    *)
      if [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] || grep -qi microsoft /proc/version 2>/dev/null; then
        wsl=1
      else
        wsl=0
      fi
      ;;
  esac
  case "$id" in
    omarchy) echo omarchy ;;
    ubuntu|arch) if [ "$wsl" = 1 ]; then echo "wsl-$id"; else echo "$id"; fi ;;
    *) return 1 ;;
  esac
}

# desktop_session: a graphical session is running (native desktops get Ghostty and fonts by default).
desktop_session() {
  [ -n "${XDG_CURRENT_DESKTOP:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]
}

# umbra_ai_access: true when umbra-ai is already here (umbrella, UM_AI_DIR, earlier clone) or the
# user's own credentials can read it (ADR 0018). Never starts a login. UM_AI_ACCESS=0|1 overrides.
umbra_ai_access() {
  case "${UM_AI_ACCESS:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  find_umbra_ai >/dev/null 2>&1 && return 0
  command -v git >/dev/null 2>&1 || return 1
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false timeout 10 \
    git ls-remote -q "$UM_AI_REPO_HTTPS" HEAD >/dev/null 2>&1 && return 0
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" timeout 15 \
    git ls-remote -q "$UM_AI_REPO_SSH" HEAD >/dev/null 2>&1
}

# The one list of components (ADR 0039): tab-separated, '-' for empty, '#' comments, a header row.
UM_CATALOG="${UM_CATALOG:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)/components.tsv}"

# catalog_platform_matches <platform> <set>: set is "all", "!<platform>" or a comma list.
catalog_platform_matches() {
  case "$2" in
    all) return 0 ;;
    '!'*) [ "$1" != "${2#!}" ] ;;
    *) [[ ",$2," == *",$1,"* ]] ;;
  esac
}

# catalog_rows <platform>: the catalog rows offered on that platform, in file (menu) order.
catalog_rows() {
  local p="$1" line id plats
  [ -r "$UM_CATALOG" ] || { log_error "Component catalog not readable: $UM_CATALOG"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    IFS=$'\t' read -r id plats _ <<<"$line"
    [ "$id" = id ] && continue
    catalog_platform_matches "$p" "$plats" && printf '%s\n' "$line"
  done <"$UM_CATALOG"
}

# selector_items <platform>: "id|label|components" per item offered on that platform, in menu order.
# Labels hold no "," (gum --selected) and no "=" (gum --label-delimiter).
selector_items() {
  local id comps label
  while IFS=$'\t' read -r id _ comps _ label _; do
    printf '%s|%s|%s\n' "$id" "$label" "$comps"
  done < <(catalog_rows "$1")
}

# selector_defaults <platform> <ai_access 0|1>: item ids pre-selected (both profiles; the work
# profile's limits are applied by the phases, ADR 0007). Comma-separated. The catalog's default
# column: yes, desktop-session (only with a desktop session), ai-access (only with Umbra AI access), no.
selector_defaults() {
  local p="$1" access="$2" id def out=()
  while IFS=$'\t' read -r id _ _ def _; do
    case "$def" in
      yes) ;;
      desktop-session) desktop_session || continue ;;
      ai-access) [ "$access" = 1 ] || continue ;;
      *) continue ;;
    esac
    out+=("$id")
  done < <(catalog_rows "$p")
  (IFS=,; echo "${out[*]}")
}

# items_to_components <platform> <ids, comma-separated>: the --components list, in menu order.
# Unknown or unavailable ids are reported on stderr and dropped.
items_to_components() {
  local p="$1" want=",$2," id comps out=() known=","
  while IFS='|' read -r id _ comps; do
    known+="$id,"
    [[ $want == *",$id,"* ]] && out+=("$comps")
  done < <(selector_items "$p")
  local w
  for w in ${2//,/ }; do
    [[ $known == *",$w,"* ]] || log_warn "Selector: '$w' is not offered on $p; ignored."
  done
  (IFS=,; echo "${out[*]}")
}

# fetch_gum: prints the path of gum $UM_GUM_VERSION: the one on PATH if it is that version,
# otherwise the pinned release, checked against install/checksums.sha256 (ADR 0016) and
# unpacked into UM_GUM_DIR (a temp dir the caller removes). Returns 1 on any failure.
fetch_gum() {
  if command -v gum >/dev/null 2>&1 && grep -q "version v\{0,1\}$UM_GUM_VERSION\b" <<<"$(gum --version 2>/dev/null || true)"; then
    command -v gum
    return 0
  fi
  local a url sha
  case "$(uname -m)" in
    aarch64|arm64) a=arm64 ;;
    *) a=x86_64 ;;
  esac
  url="https://github.com/charmbracelet/gum/releases/download/v${UM_GUM_VERSION}/gum_${UM_GUM_VERSION}_Linux_${a}.tar.gz"
  sha="$(pinned_sha256 "$url")"
  [ -n "$sha" ] || { log_error "No pinned sha256 for $url."; return 1; }
  : "${UM_GUM_DIR:?UM_GUM_DIR must name a temp dir}"
  curl -fsSL -o "$UM_GUM_DIR/gum.tar.gz" "$url" || { log_error "Download failed: $url"; return 1; }
  if ! verify_sha256 "$UM_GUM_DIR/gum.tar.gz" "$sha"; then
    log_error "sha256 mismatch for $url; not running gum."
    return 1
  fi
  tar -xz -C "$UM_GUM_DIR" -f "$UM_GUM_DIR/gum.tar.gz" || { log_error "Unpacking gum failed."; return 1; }
  echo "$UM_GUM_DIR/gum_${UM_GUM_VERSION}_Linux_${a}/gum"
}

# select_with_gum <gum> <platform> <defaults> <ai_access>: interactive multi-select; prints the
# chosen ids, comma-separated. Umbra AI without access is shown with the reason and not selectable.
select_with_gum() {
  local gum="$1" p="$2" defaults=",$3," access="$4" id label opts=() sel=() chosen
  while IFS='|' read -r id label _; do
    if [ "$id" = umbra-ai ] && [ "$access" != 1 ]; then
      continue
    fi
    opts+=("$label=$id")
    [[ $defaults == *",$id,"* ]] && sel+=("$label")
  done < <(selector_items "$p")
  if [ "$access" != 1 ]; then
    log_warn "$UM_AI_PRIVATE_MSG"
  fi
  chosen="$("$gum" choose --no-limit --label-delimiter="=" \
    --header="Umbra · $p — space to toggle, enter to install" \
    --selected="$(IFS=,; echo "${sel[*]}")" "${opts[@]}" </dev/tty)" || return 1
  echo "$chosen" | paste -sd, -
}

# setup_arch: the GoReleaser arch name of this machine.
setup_arch() {
  case "$(uname -m)" in
    aarch64 | arm64) echo arm64 ;;
    *) echo amd64 ;;
  esac
}

# fetch_setup: prints the path of a verified umbra-setup $UM_SETUP_VERSION, unpacked into
# UM_GUM_DIR. Returns 1 when it is not available (no pin, download failed): the caller uses the gum
# menu. Returns 2 when a check fails (sha256, signature, attestation): a sign of tampering, so the
# caller stops instead of falling back. Required: the
# sha256 pinned in checksums.sha256 for the release URL. When installed: cosign checks the keyless
# signature of checksums.txt (identity: the release workflow at the tag), and gh checks the build
# provenance attestation; a failure of either stops (ADR 0038). UM_SETUP_DOWNLOAD_BASE replaces the
# download base for tests; the pin is always looked up by the GitHub release URL.
fetch_setup() {
  local ver="$UM_SETUP_VERSION" asset url sha base dir
  if [ -z "$ver" ]; then
    log_info "umbra-setup has no pinned release yet; using the gum menu."
    return 1
  fi
  asset="umbra-setup_${ver}_linux_$(setup_arch).tar.gz"
  url="$UM_SETUP_REPO_URL/releases/download/v$ver/$asset"
  sha="$(pinned_sha256 "$url")"
  if [ -z "$sha" ]; then
    log_warn "No pinned sha256 for $url; using the gum menu."
    return 1
  fi
  base="${UM_SETUP_DOWNLOAD_BASE:-$UM_SETUP_REPO_URL/releases/download/v$ver}"
  : "${UM_GUM_DIR:?UM_GUM_DIR must name a temp dir}"
  dir="$UM_GUM_DIR/setup"
  mkdir -p "$dir"
  curl -fsSL -o "$dir/$asset" "$base/$asset" || { log_warn "Download failed: $base/$asset; using the gum menu."; return 1; }
  if ! verify_sha256 "$dir/$asset" "$sha"; then
    log_error "sha256 mismatch for $asset; not running it."
    return 2
  fi
  setup_check_signature "$base" "$dir" "$asset" "$ver" "$sha" || return 2
  setup_check_attestation "$dir/$asset" || return 2
  tar -xz -C "$dir" -f "$dir/$asset" umbra-setup || { log_error "Unpacking $asset failed."; return 1; }
  echo "$dir/umbra-setup"
}

# setup_check_signature <base> <dir> <asset> <version> <sha256>: cosign verify-blob on checksums.txt,
# then the asset's line in it must be the pinned sha256. Skipped (said once) without cosign.
setup_check_signature() {
  local base="$1" dir="$2" asset="$3" ver="$4" sha="$5" listed
  if ! command -v cosign >/dev/null 2>&1; then
    log_info "cosign not installed; the signature of checksums.txt is not checked (the pinned sha256 is)."
    return 0
  fi
  if ! curl -fsSL -o "$dir/checksums.txt" "$base/checksums.txt" \
    || ! curl -fsSL -o "$dir/checksums.txt.sigstore.json" "$base/checksums.txt.sigstore.json"; then
    log_error "Could not download checksums.txt and its signature."
    return 1
  fi
  if ! cosign verify-blob \
    --certificate-identity "$UM_SETUP_REPO_URL/.github/workflows/release.yml@refs/tags/v$ver" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    --bundle "$dir/checksums.txt.sigstore.json" "$dir/checksums.txt" >/dev/null 2>&1; then
    log_error "The signature check failed for checksums.txt of umbra-setup v$ver; not running it."
    return 1
  fi
  listed="$(awk -v a="$asset" '$2 == a { print $1 }' "$dir/checksums.txt")"
  if [ "$listed" != "$sha" ]; then
    log_error "The signed checksums.txt does not list the pinned sha256 for $asset; not running it."
    return 1
  fi
}

# setup_check_attestation <file>: gh attestation verify against the bootstrapper repo. Skipped
# (said once) when gh is missing, not logged in, or has no attestation command.
setup_check_attestation() {
  if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1 || ! gh attestation --help >/dev/null 2>&1; then
    log_info "gh not logged in (or too old); the build provenance attestation is not checked."
    return 0
  fi
  if ! gh attestation verify "$1" -R "${UM_SETUP_REPO_URL#https://github.com/}" >/dev/null 2>&1; then
    log_error "The attestation check failed for $(basename "$1"); not running it."
    return 1
  fi
}

# install_setup_bin <file>: copies the verified binary to ~/.local/bin/umbra-setup and prints the
# path to run. An umbra-setup there that is not ours is kept, and the temp copy is printed instead.
install_setup_bin() {
  local src="$1" dest="$HOME/.local/bin/umbra-setup"
  if [ -e "$dest" ] && ! "$dest" --version 2>/dev/null | grep -q '(Umbra bootstrapper)$'; then
    log_warn "$dest is not Umbra's; it is not overwritten. Running the verified copy once."
    echo "$src"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  install -m 0755 "$src" "$dest" && echo "$dest"
}

