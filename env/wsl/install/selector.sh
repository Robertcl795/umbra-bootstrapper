#!/usr/bin/env bash
# selector.sh — platform detection and the component selector of install.sh
# (ADR 0016, docs/plans/platform.md §3-4 in the Umbra umbrella). Sourced after common.sh.

UM_GUM_VERSION="2.0.2"
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

# selector_items <platform>: "id|label|components" per item offered on that platform, in menu order.
# Labels hold no "," (gum --selected) and no "=" (gum --label-delimiter).
selector_items() {
  local p="$1"
  if [ "$p" = omarchy ]; then
    echo "packages|Extra tools (pacman -S --needed; Omarchy keeps its own)|packages"
  else
    echo "packages|Packages and base tools|packages"
  fi
  echo "shell|Shell: zsh (fish theme-only)|shell"
  echo "prompt|Prompt: Starship|prompt"
  if [ "$p" != omarchy ]; then
    echo "nvim|Neovim|nvim"
    echo "k8s|Kubernetes tools|k8s"
    echo "zellij|Zellij|zellij"
    echo "lang|Language toolchains|lang"
    echo "fastfetch|fastfetch|fastfetch"
  fi
  case "$p" in
    wsl-*) echo "wsl|WSL tuning|wsl" ;;
    ubuntu|arch) echo "desktop|Desktop: Ghostty + JetBrainsMono Nerd Font|desktop" ;;
  esac
  echo "umbra-ai|Umbra AI: um · vault · AI standard · AI CLIs · Ollama|ai-cli,ai-standard,um,vault,ollama"
}

# selector_defaults <platform> <ai_access 0|1>: item ids pre-selected (both profiles; the work
# profile's limits are applied by the phases, ADR 0007). Comma-separated.
selector_defaults() {
  local p="$1" access="$2" id out=()
  while IFS='|' read -r id _ _; do
    case "$id" in
      desktop) desktop_session || continue ;;
      umbra-ai) [ "$access" = 1 ] || continue ;;
    esac
    out+=("$id")
  done < <(selector_items "$p")
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
