#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# chezmoi deploys the dotfiles (ADR 0006). Arch and Omarchy: pacman. Ubuntu has no
# package, so the pinned release .deb is used, checked against install/checksums.sha256.
UM_CHEZMOI_VERSION="2.73.3"

install_chezmoi() {
  log_step "chezmoi"
  if ensure_cmd chezmoi; then
    log_info "chezmoi already installed: $(chezmoi --version | head -n 1)"
    return 0
  fi
  local id=""
  [ -f /etc/os-release ] && id="$(. /etc/os-release && echo "${ID:-}")"
  case "$id" in
    arch|omarchy)
      run_priv pacman -S --noconfirm --needed chezmoi
      ;;
    ubuntu)
      local url tmp sha
      url="https://github.com/twpayne/chezmoi/releases/download/v${UM_CHEZMOI_VERSION}/chezmoi_${UM_CHEZMOI_VERSION}_linux_$(detect_arch).deb"
      sha="$(pinned_sha256 "$url")"
      [ -n "$sha" ] || die "No pinned sha256 for $url in install/checksums.sha256."
      tmp="$(mktemp -d)"
      curl -fsSL -o "$tmp/chezmoi.deb" "$url" || { rm -rf "$tmp"; die "Download failed: $url"; }
      if ! verify_sha256 "$tmp/chezmoi.deb" "$sha"; then
        rm -rf "$tmp"
        die "sha256 mismatch for $url; not installing chezmoi."
      fi
      run_priv dpkg -i "$tmp/chezmoi.deb"
      rm -rf "$tmp"
      ;;
    *)
      die "No chezmoi install method for '${id:-unknown}'."
      ;;
  esac
  log_info "chezmoi installed: $(chezmoi --version | head -n 1)"
}

if [ "${1:-}" = "--run" ]; then
  install_chezmoi
fi
