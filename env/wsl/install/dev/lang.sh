#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Language toolchain managers: rustup (Rust), fnm (Node.js), uv (Python).
# Everything lands in the current process PATH too, so later install steps
# (and the current WSL session) can use the tools without a re-login.

install_rustup() {
  # idempotency-fix: rustup lives in ~/.cargo/bin, which a fresh bash has not on PATH yet.
  # shellcheck disable=SC1091
  [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
  if ! ensure_cmd rustup; then
    log_info "Installing rustup..."
    case "${UM_OS:-}" in
      arch) run_priv pacman -S --noconfirm --needed rustup ;;
      *) curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path ;;
    esac
  fi
  # shellcheck disable=SC1091
  [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
  export PATH="$HOME/.cargo/bin:$PATH"

  if ! rustup show active-toolchain >/dev/null 2>&1; then
    log_info "Installing stable Rust toolchain..."
    rustup default stable
  fi
  log_info "Rust: $(rustc --version 2>/dev/null || echo 'toolchain pending')"
}

install_fnm() {
  if ! ensure_cmd fnm; then
    log_info "Installing fnm (Fast Node Manager)..."
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$HOME/.local/bin" --skip-shell \
      || { log_warn "fnm installer failed."; return 1; }
  fi
  export PATH="$HOME/.local/bin:$PATH"
  ensure_cmd fnm || { log_warn "fnm not on PATH; skipping Node.js setup."; return 1; }

  if [ -z "$(fnm ls 2>/dev/null | grep -v system || true)" ]; then
    log_info "Installing Node.js LTS via fnm..."
    fnm install --lts \
      || { log_warn "Could not install Node LTS (network?); run 'fnm install --lts' later."; return 1; }
  fi

  # Make the LTS the default so every new shell (and the rest of this
  # install) gets node without an explicit 'fnm use'.
  if ! fnm ls 2>/dev/null | grep -q default; then
    log_info "Setting Node.js LTS as the fnm default..."
    fnm default lts-latest || log_warn "Could not set default Node version; run 'fnm default lts-latest' later."
  fi
  eval "$(fnm env --shell bash 2>/dev/null)" || true
  fnm use default >/dev/null 2>&1 || true
  log_info "Node: $(node --version 2>/dev/null || echo 'not on PATH yet (open a new shell)')"
}

install_pnpm() {
  # Standalone pnpm: self-contained binary in PNPM_HOME, no corepack (and no
  # dependency on the node version fnm happens to have active).
  export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
  case ":$PATH:" in
    *":$PNPM_HOME:"*) ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
  esac
  # idempotency-fix: current pnpm installers (v12 seen in tests) put the binary in $PNPM_HOME/bin.
  case ":$PATH:" in
    *":$PNPM_HOME/bin:"*) ;;
    *) export PATH="$PNPM_HOME/bin:$PATH" ;;
  esac

  if ! ensure_cmd pnpm; then
    log_info "Installing pnpm (standalone script, no corepack)..."
    # SHELL is pinned to bash so the installer only ever touches ~/.bashrc;
    # zsh/fish PATH setup is handled by the Umbra shell configs themselves.
    curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME="$PNPM_HOME" SHELL="$(command -v bash)" sh - \
      || log_warn "pnpm installer failed; run later: curl -fsSL https://get.pnpm.io/install.sh | sh -"
  fi
  log_info "pnpm: $(pnpm --version 2>/dev/null || echo 'not on PATH yet (open a new shell)')"
}

install_uv() {
  if ! ensure_cmd uv; then
    log_info "Installing uv (Python package/environment manager)..."
    case "${UM_OS:-}" in
      arch) run_priv pacman -S --noconfirm --needed uv ;;
      *) curl -fsSL https://astral.sh/uv/install.sh | sh ;;
    esac
  fi
  export PATH="$HOME/.local/bin:$PATH"
  log_info "uv: $(uv --version 2>/dev/null || echo 'not on PATH yet')"
}

install_lang_toolchains() {
  log_step "Phase 8: Language toolchains (rustup / fnm+pnpm / uv)"
  install_rustup
  if install_fnm; then
    install_pnpm
  else
    log_warn "Skipping pnpm (Node.js setup did not complete)."
  fi
  install_uv
}

if [ "${1:-}" = "--run" ]; then
  install_lang_toolchains
fi
