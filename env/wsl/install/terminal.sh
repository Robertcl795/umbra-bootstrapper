#!/usr/bin/env bash
# terminal.sh — the Windows side of the theme, from inside WSL (ADR 0043). Every write is per
# user, needs no admin and is undone by the matching remove:
#   --run          component terminal: the Windows Terminal fragment (the Umbra schemes and an
#                  "Umbra · <distro>" profile of its own) and JetBrainsMono Nerd Font for this user
#   --remove       the fragment folder, the font files and their registry values
#   --pwsh         component pwsh: starship through winget, Umbra's starship.toml, one marked block
#                  in each PowerShell $PROFILE. The execution policy is read, never changed.
#   --pwsh-remove  the blocks and Umbra's starship.toml (starship stays: winget uninstall Starship.Starship)
# Sourced without arguments it only defines its functions (env/wsl/tests/unit_terminal.sh).
# Tests set UM_WIN_LOCALAPPDATA_U/_W (Linux and Windows paths) and UM_WIN_PROFILES (one per line).
set -euo pipefail

TERMINAL_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]:-${0:-}}")" && pwd)"
# shellcheck disable=SC1090,SC1091
source "$TERMINAL_DIR/common.sh"

UM_NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.tar.xz"
UM_NERD_FONT="JetBrainsMono Nerd Font"
UM_FONT_FALLBACK="Cascadia Mono"
UM_FONT_STYLES=(Regular Bold Italic BoldItalic)
UM_FONT_KEY='HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
UM_BLOCK_START='# >>> umbra prompt >>> (added by Umbra; terminal.sh --pwsh-remove takes it out)'
UM_BLOCK_END='# <<< umbra prompt <<<'

# win_run <cmd...>: a Windows program from a Windows-side cwd (no UNC-path warning).
win_run() { (cd /mnt/c 2>/dev/null || true; "$@"); }

# localappdata: sets LA_U and LA_W, or returns 1 (no interop).
localappdata() {
  LA_W="${UM_WIN_LOCALAPPDATA_W:-}"
  LA_U="${UM_WIN_LOCALAPPDATA_U:-}"
  if [ -z "$LA_W" ]; then
    LA_W="$(win_run cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r' || true)"
  fi
  if [ -z "$LA_U" ] && [ -n "$LA_W" ]; then
    LA_U="$(wslpath -u "$LA_W" 2>/dev/null || true)"
  fi
  [ -n "$LA_W" ] && [ -n "$LA_U" ] && [ -d "$LA_U" ]
}

fragment_dir() { echo "$LA_U/Microsoft/Windows Terminal/Fragments/Umbra"; }
fonts_dir() { echo "$LA_U/Microsoft/Windows/Fonts"; }
font_file() { echo "JetBrainsMonoNerdFont-$1.ttf"; }
font_value() {
  local style="$1"
  [ "$style" != BoldItalic ] || style="Bold Italic"
  echo "$UM_NERD_FONT $style (TrueType)"
}

# fetch_font <dir>: the pinned archive, sha256-checked, and its four styles into <dir>.
fetch_font() {
  local dir="$1" sha tmp s
  sha="$(pinned_sha256 "$UM_NERD_FONT_URL")"
  [ -n "$sha" ] || { log_warn "No pinned sha256 for $UM_NERD_FONT_URL."; return 1; }
  tmp="$(mktemp -d)"
  if ! curl -fsSL -o "$tmp/font.tar.xz" "$UM_NERD_FONT_URL" || ! verify_sha256 "$tmp/font.tar.xz" "$sha"; then
    rm -rf "$tmp"
    log_warn "The font download failed or did not match its sha256."
    return 1
  fi
  for s in "${UM_FONT_STYLES[@]}"; do
    tar -xJ -C "$dir" -f "$tmp/font.tar.xz" "$(font_file "$s")" || { rm -rf "$tmp"; return 1; }
  done
  rm -rf "$tmp"
}

# font_install: the four files in the per-user Fonts folder, each registered under HKCU.
font_install() {
  local dest s have=1 tmp
  dest="$(fonts_dir)"
  for s in "${UM_FONT_STYLES[@]}"; do [ -f "$dest/$(font_file "$s")" ] || have=0; done
  if [ "$have" = 1 ]; then
    log_info "$UM_NERD_FONT is already installed for this Windows user."
    return 0
  fi
  tmp="$(mktemp -d)"
  fetch_font "$tmp" || { rm -rf "$tmp"; return 1; }
  mkdir -p "$dest"
  for s in "${UM_FONT_STYLES[@]}"; do
    cp "$tmp/$(font_file "$s")" "$dest/" || { rm -rf "$tmp"; return 1; }
    win_run reg.exe add "$UM_FONT_KEY" /v "$(font_value "$s")" /t REG_SZ /d "$LA_W\\Microsoft\\Windows\\Fonts\\$(font_file "$s")" /f >/dev/null ||
      { rm -rf "$tmp"; return 1; }
  done
  rm -rf "$tmp"
  log_info "$UM_NERD_FONT installed for this Windows user (no admin). Restart Windows Terminal to see it."
}

font_remove() {
  local dest s
  dest="$(fonts_dir)"
  for s in "${UM_FONT_STYLES[@]}"; do
    win_run reg.exe delete "$UM_FONT_KEY" /v "$(font_value "$s")" /f >/dev/null 2>&1 || true
    rm -f "$dest/$(font_file "$s")" 2>/dev/null || log_warn "$(font_file "$s") is in use; close Windows Terminal and run this again."
  done
}

# fragment_write <font>: umbra-setup prints the fragment (internal/theme, tested there).
fragment_write() {
  local font="$1" bin="${UM_SETUP_BIN:-$HOME/.local/bin/umbra-setup}" dir tmp
  if [ ! -x "$bin" ]; then
    log_warn "No umbra-setup at $bin: the Windows Terminal profile is not written."
    return 0
  fi
  dir="$(fragment_dir)"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.umbra.XXXXXX")"
  if WSL_DISTRO_NAME="${WSL_DISTRO_NAME:-}" "$bin" --wt-fragment "${UM_THEME:-umbra}" --wt-font "$font" >"$tmp"; then
    mv "$tmp" "$dir/umbra.json"
    log_info "Windows Terminal: profile \"Umbra · ${WSL_DISTRO_NAME:-}\" with the ${UM_THEME:-umbra} scheme. Restart Windows Terminal (a running one loads it on its next settings reload), then open it from the tab menu."
  else
    rm -f "$tmp"
    log_warn "umbra-setup could not print the Windows Terminal fragment."
  fi
}

# wt_settings: Windows Terminal's settings.json files here (stable, Preview, unpackaged).
wt_settings() {
  local f
  for f in "$LA_U/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" \
    "$LA_U/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json" \
    "$LA_U/Microsoft/Windows Terminal/settings.json"; do
    [ -f "$f" ] && echo "$f"
  done
  return 0
}

# wt_defaults <settings.json>: the "profiles.defaults" object, as text (// comments dropped).
# Read only: Umbra never writes settings.json (ADR 0043, G-B3, operator: tell the user only).
wt_defaults() {
  awk '
    { sub(/^[ \t]*\/\/.*$/, "") }
    !on && /"defaults"[ \t]*:/ { on = 1; sub(/.*"defaults"[ \t]*:/, "") }
    on {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "{") d++
        if (c == "}") { d--; if (d == 0) { print substr($0, 1, i); exit } }
      }
      print
    }' "$1"
}

# defaults_hint <scheme> <font>: a profiles.defaults scheme or font outranks the fragment's
# profile (seen on Windows Terminal 1.24); say which and where to change the Umbra profile.
defaults_hint() {
  local want="$1" font="$2" f block scheme face
  while IFS= read -r f; do
    block="$(wt_defaults "$f")"
    scheme="$(grep -o '"colorScheme"[[:space:]]*:[[:space:]]*"[^"]*"' <<<"$block" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')"
    face="$(grep -o '"face"[[:space:]]*:[[:space:]]*"[^"]*"\|"fontFace"[[:space:]]*:[[:space:]]*"[^"]*"' <<<"$block" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')"
    [ -n "$scheme$face" ] || continue
    log_warn "Your Windows Terminal profiles.defaults sets${scheme:+ colorScheme \"$scheme\"}${scheme:+${face:+ and}}${face:+ font \"$face\"}, which outranks the Umbra profile."
    log_warn "To use Umbra there: Settings > Umbra · ${WSL_DISTRO_NAME:-} > Appearance > Color scheme: $want${face:+, Font face: $font}. Umbra does not edit settings.json."
    return 0
  done < <(wt_settings)
}

terminal_install() {
  log_step "Windows Terminal: Umbra profile, schemes and $UM_NERD_FONT"
  localappdata || { log_warn "The Windows side is not reachable (interop off?); skipping."; return 0; }
  local font="$UM_NERD_FONT"
  if ! font_install; then
    font="$UM_FONT_FALLBACK"
    log_warn "$UM_NERD_FONT is not installed; the profile uses $UM_FONT_FALLBACK."
  fi
  fragment_write "$font"
  defaults_hint "$(scheme_name "${UM_THEME:-umbra}")" "$font"
}

scheme_name() {
  case "$1" in
    void) echo "Umbra Void" ;;
    lux) echo "Umbra Lux" ;;
    *) echo "Umbra" ;;
  esac
}

terminal_remove() {
  localappdata || { log_warn "The Windows side is not reachable; nothing removed."; return 0; }
  rm -rf "$(fragment_dir)"
  font_remove
  log_info "Removed the Windows Terminal fragment and $UM_NERD_FONT."
}

# pwsh_block: the lines added to $PROFILE.
pwsh_block() {
  printf '%s\n' "$UM_BLOCK_START" \
    'if (Get-Command starship -ErrorAction SilentlyContinue) {' \
    "  \$env:STARSHIP_CONFIG = Join-Path \$env:LOCALAPPDATA 'umbra\\starship.toml'" \
    '  Invoke-Expression (&starship init powershell)' \
    '}' \
    "$UM_BLOCK_END"
}

# profiles: one Linux path per line, for each PowerShell that is here.
profiles() {
  if [ -n "${UM_WIN_PROFILES:-}" ]; then
    printf '%s\n' "$UM_WIN_PROFILES"
    return 0
  fi
  local ps p
  for ps in powershell.exe pwsh.exe; do
    command -v "$ps" >/dev/null 2>&1 || continue
    # shellcheck disable=SC2016 # $PROFILE is PowerShell's, not bash's
    p="$(win_run "$ps" -NoProfile -Command '$PROFILE.CurrentUserCurrentHost' </dev/null 2>/dev/null | tr -d '\r' || true)"
    [ -z "$p" ] || wslpath -u "$p" 2>/dev/null || true
  done
}

# block_strip <file>: the file without the block (lines compared without a trailing CR).
block_strip() {
  awk -v s="$UM_BLOCK_START" -v e="$UM_BLOCK_END" '
    { l = $0; sub(/\r$/, "", l) }
    l == s { skip = 1; next }
    skip && l == e { skip = 0; next }
    !skip { print }' "$1"
}

# block_add <file>: replaces any block with a fresh one, in the file's own line ending.
block_add() {
  local f="$1" eol=$'\n' tmp
  mkdir -p "$(dirname "$f")"
  [ -e "$f" ] || : >"$f"
  ! grep -q $'\r$' "$f" || eol=$'\r\n'
  tmp="$(mktemp)"
  block_strip "$f" >"$tmp"
  if [ -s "$tmp" ] && [ -n "$(tail -c 1 "$tmp")" ]; then printf '%s' "$eol" >>"$tmp"; fi
  pwsh_block | while IFS= read -r line; do printf '%s%s' "$line" "$eol"; done >>"$tmp"
  cat "$tmp" >"$f"
  rm -f "$tmp"
}

pwsh_install() {
  log_step "PowerShell prompt: Starship"
  localappdata || { log_warn "The Windows side is not reachable (interop off?); skipping."; return 0; }
  if ! command -v starship.exe >/dev/null 2>&1; then
    win_run winget.exe install --id Starship.Starship --exact --source winget --accept-package-agreements --accept-source-agreements --silent ||
      log_warn "winget could not install Starship; the block waits for it (it runs only when starship is found)."
  fi
  mkdir -p "$LA_U/umbra"
  cp "$UM_ENV_DIR/../.chezmoitemplates/starship/${UM_THEME:-umbra}.toml" "$LA_U/umbra/starship.toml"
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    block_add "$p"
    log_info "PowerShell profile: $p"
  done < <(profiles)
  local policy
  policy="$(win_run powershell.exe -NoProfile -Command Get-ExecutionPolicy </dev/null 2>/dev/null | tr -d '\r' || true)"
  case "$policy" in
    Restricted | AllSigned)
      log_warn "Windows PowerShell's execution policy is $policy: it will not load your profile, so the prompt shows only in PowerShell 7."
      log_warn "Umbra does not change it. To allow profiles for your user, run in PowerShell: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
      ;;
  esac
}

pwsh_remove() {
  localappdata || { log_warn "The Windows side is not reachable; nothing removed."; return 0; }
  local p tmp
  while IFS= read -r p; do
    if [ -z "$p" ] || [ ! -f "$p" ]; then continue; fi
    tmp="$(mktemp)"
    block_strip "$p" >"$tmp"
    cat "$tmp" >"$p"
    rm -f "$tmp"
  done < <(profiles)
  rm -f "$LA_U/umbra/starship.toml"
  rmdir "$LA_U/umbra" 2>/dev/null || true
  log_info "Removed the Umbra prompt block. Starship stays installed: winget uninstall Starship.Starship"
}

case "${1:-}" in
  --run) terminal_install ;;
  --remove) terminal_remove ;;
  --pwsh) pwsh_install ;;
  --pwsh-remove) pwsh_remove ;;
esac
