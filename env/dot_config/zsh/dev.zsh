# Development environment hooks (Rust / Node / Python / AI CLIs)
# Sourced by shells/zsh/zshrc. Everything is guarded: a missing tool
# never breaks shell startup.

# ---------- Rust (rustup/cargo) ----------
if [ -f "$HOME/.cargo/env" ]; then
  source "$HOME/.cargo/env"
elif [ -d "$HOME/.cargo/bin" ]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

# ---------- Node (fnm) ----------
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

# ---------- pnpm (standalone, no corepack) ----------
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
if [ -d "$PNPM_HOME" ]; then
  case ":$PATH:" in
    *":$PNPM_HOME:"*) ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
  esac
  # idempotency-fix: current pnpm installers (v12 seen in tests) put the binary in $PNPM_HOME/bin.
  if [ -d "$PNPM_HOME/bin" ]; then
    case ":$PATH:" in
      *":$PNPM_HOME/bin:"*) ;;
      *) export PATH="$PNPM_HOME/bin:$PATH" ;;
    esac
  fi
fi

# ---------- Python (uv) ----------
# uv installs into ~/.local/bin (already on PATH). Enable completions.
if command -v uv >/dev/null 2>&1; then
  eval "$(uv generate-shell-completion zsh 2>/dev/null)" 2>/dev/null || true
fi

# ---------- AI CLIs ----------
# opencode installs into ~/.opencode/bin
if [ -d "$HOME/.opencode/bin" ]; then
  export PATH="$HOME/.opencode/bin:$PATH"
fi

# claude installs into ~/.local/bin (already on PATH)
