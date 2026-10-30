#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Desktop pieces on native Ubuntu and Arch (ADR 0017): Ghostty and JetBrainsMono Nerd Font.
# chezmoi deploys ~/.config/ghostty (theme generated from the brand tokens). Never touched:
# the display manager, desktop settings, /etc beyond package installs, system fonts, the
# default-terminal setting, other terminals' configs.
UM_NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.tar.xz"

running_in_wsl() {
  case "${UM_IS_WSL:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  grep -qi microsoft /proc/version 2>/dev/null
}

install_font_ubuntu() {
  local dest="$HOME/.local/share/fonts/umbra" sha tmp
  if grep -qi "JetBrainsMono Nerd Font" <<<"$(fc-list 2>/dev/null || true)"; then
    log_info "JetBrainsMono Nerd Font already installed."
    return 0
  fi
  sha="$(pinned_sha256 "$UM_NERD_FONT_URL")"
  [ -n "$sha" ] || die "No pinned sha256 for $UM_NERD_FONT_URL in install/checksums.sha256."
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/font.tar.xz" "$UM_NERD_FONT_URL" || { rm -rf "$tmp"; die "Download failed: $UM_NERD_FONT_URL"; }
  if ! verify_sha256 "$tmp/font.tar.xz" "$sha"; then
    rm -rf "$tmp"
    die "sha256 mismatch for $UM_NERD_FONT_URL; not installing the font."
  fi
  mkdir -p "$dest"
  tar -xJ -C "$dest" -f "$tmp/font.tar.xz" --wildcards '*.ttf'
  rm -rf "$tmp"
  fc-cache -f "$dest" >/dev/null
  log_info "JetBrainsMono Nerd Font installed into $dest."
}

install_desktop() {
  log_step "Desktop: Ghostty + JetBrainsMono Nerd Font (native only)"

  if running_in_wsl; then
    log_info "WSL: the Windows side owns the terminal and fonts; skipping."
    return 0
  fi

  case "${UM_OS:-}" in
    ubuntu)
      # Ubuntu 26.04 ships Ghostty in its archive (checked 2026-10-29); no unpinned download.
      local policy
      policy="$(apt-cache policy ghostty 2>/dev/null || true)"
      if ! grep -q 'Candidate: [0-9]' <<<"$policy"; then
        die "Ghostty is not in this Ubuntu release's archive; install it yourself, then re-run with --skip desktop."
      fi
      run_priv apt-get install -y ghostty fontconfig xz-utils
      install_font_ubuntu
      ;;
    arch)
      run_priv pacman -S --noconfirm --needed ghostty ttf-jetbrains-mono-nerd
      ;;
    *)
      log_info "Desktop pieces are for native Ubuntu and Arch only; skipping on '${UM_OS:-unknown}'."
      return 0
      ;;
  esac

  log_info "Ghostty $(ghostty --version 2>/dev/null | head -n 1 || true) installed; config managed by chezmoi."
}

if [ "${1:-}" = "--run" ]; then
  install_desktop
fi
