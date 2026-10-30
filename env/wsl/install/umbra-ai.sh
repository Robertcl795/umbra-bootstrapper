#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Umbra AI (ADR 0018), the parts not covered by the ai-cli and ai-standard phases:
#   um     the `um` CLI from umbra-ai, linked into ~/.local/bin
#   vault  clone your private vault (UM_VAULT_REPO, personal profile only) or `um init`
#   ollama local models runtime; nothing is pulled and no service is started
# Work profile (ADR 0007): no private vault clone (um init in work mode), Ollama binary only.
UM_OLLAMA_VERSION="0.40.13"

install_um() {
  find_umbra_ai >/dev/null 2>&1 || clone_umbra_ai
  local ai
  ai="$(find_umbra_ai)" || { log_warn "umbra-ai not found (it is private); skipping um."; return 0; }
  bash "$ai/cli/install.sh" --no-init
}

setup_vault() {
  local vault="${UM_VAULT:-$HOME/vault}" um="$HOME/.local/bin/um"
  if [ -d "$vault" ]; then
    log_info "Vault already present at $vault."
    return 0
  fi
  if [ -n "${UM_VAULT_REPO:-}" ] && [ "${UM_MODE:-personal}" = "personal" ]; then
    log_info "Cloning your private vault into $vault"
    if GIT_TERMINAL_PROMPT=0 git clone -q "$UM_VAULT_REPO" "$vault"; then
      return 0
    fi
    log_warn "Could not clone UM_VAULT_REPO; starting from the template instead."
  elif [ -n "${UM_VAULT_REPO:-}" ]; then
    log_info "Work profile: the private vault is not cloned (ADR 0007)."
  fi
  [ -x "$um" ] || { log_warn "um is not installed; skipping the vault (select um too)."; return 0; }
  UM_VAULT="$vault" UM_MODE="${UM_MODE:-personal}" "$um" init
  log_info "Vault created from vault-template at $vault. To use an existing vault, set UM_VAULT_REPO."
}

install_ollama() {
  if ensure_cmd ollama; then
    log_info "Ollama already installed: $(ollama --version 2>/dev/null | tail -n 1)"
    return 0
  fi
  case "${UM_OS:-}" in
    arch|omarchy)
      run_priv pacman -S --noconfirm --needed ollama
      ;;
    ubuntu)
      local url sha tmp dest="$HOME/.local/share/umbra/ollama"
      local arch
      arch="$(detect_arch)"
      url="https://github.com/ollama/ollama/releases/download/v${UM_OLLAMA_VERSION}/ollama-linux-${arch}.tar.zst"
      sha="$(pinned_sha256 "$url")"
      [ -n "$sha" ] || die "No pinned sha256 for $url in install/checksums.sha256."
      run_priv apt-get install -y zstd
      tmp="$(mktemp -d)"
      log_info "Downloading Ollama ${UM_OLLAMA_VERSION} (about 1.5 GB)"
      curl -fsSL -o "$tmp/ollama.tar.zst" "$url" || { rm -rf "$tmp"; die "Download failed: $url"; }
      if ! verify_sha256 "$tmp/ollama.tar.zst" "$sha"; then
        rm -rf "$tmp"
        die "sha256 mismatch for $url; not installing Ollama."
      fi
      rm -rf "$dest" && mkdir -p "$dest" "$HOME/.local/bin"
      tar --zstd -x -C "$dest" -f "$tmp/ollama.tar.zst"
      rm -rf "$tmp"
      ln -sfn "$dest/bin/ollama" "$HOME/.local/bin/ollama"
      ;;
    *)
      log_warn "No Ollama install method for '${UM_OS:-unknown}'; skipping."
      return 0
      ;;
  esac
  if [ "${UM_MODE:-personal}" = "work" ]; then
    log_info "Work profile: Ollama installed, no models pulled; keep it offline (ADR 0007)."
  else
    log_info "Ollama installed; pull a model with: ollama pull <model>"
  fi
}

install_umbra_ai() {
  log_step "Umbra AI: um, vault, Ollama"
  if component_enabled um; then install_um; fi
  if component_enabled vault; then setup_vault; fi
  if component_enabled ollama; then install_ollama; fi
}

if [ "${1:-}" = "--run" ]; then
  install_umbra_ai
fi
