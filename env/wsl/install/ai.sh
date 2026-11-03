#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Phase 11: the AI-Standard, through `um ai setup` (umbra-ai tools/umbra_ai.py):
#   links the global layer of each chosen agent (Claude Code: ~/.claude/rules, skills, agents;
#   Antigravity: ~/.gemini/config/rules, skills), and records mode, agents and profile.
# Work profile (ADR 0007): the generic standard for the allowed agents only; no MCP server.
# Personal profile: also the local context DB (uv) and its MCP registration with Claude Code.
#   UM_AI_AGENTS  comma-separated agents for setup (default: claude)

install_ai_standard() {
  log_step "Phase 11: AI-Standard"

  find_umbra_ai >/dev/null 2>&1 || clone_umbra_ai
  local ai_dir mode="${UM_MODE:-personal}"
  ai_dir="$(find_ai_standard)" || {
    log_warn "AI-Standard not found (set UM_AI_DIR or clone umbra-ai); skipping."
    return 0
  }

  python3 -I "$ai_dir/tools/umbra_ai.py" setup --mode "$mode" --agents "${UM_AI_AGENTS:-claude}" --yes \
    || { log_warn "um ai setup failed; run it again: um ai setup"; return 0; }

  if [ "$mode" = "work" ]; then
    log_info "Work profile: no MCP server and no context DB (ADR 0007)."
    return 0
  fi

  # Vector context DB environment (uv is installed by install/dev/lang.sh)
  export PATH="$HOME/.local/bin:$PATH"
  if ensure_cmd uv; then
    log_info "Syncing vector context DB environment (uv)..."
    (cd "$ai_dir/context" && uv sync) || log_warn "uv sync failed; run manually: uv sync (in umbra-ai/context)."
  else
    log_warn "uv not found; skipping context DB env. Re-run after install/dev/lang.sh."
  fi

  # Register the MCP server with Claude Code (user scope, idempotent)
  if ensure_cmd claude; then
    # idempotency-fix: read the user-scope config instead of `claude mcp list`, which
    # rewrites ~/.claude.json (with a backup) and starts every MCP server on each run.
    if ! grep -q '"context-db"' "$HOME/.claude.json" 2>/dev/null; then
      log_info "Registering context-db MCP server with Claude Code..."
      claude mcp add --scope user context-db -- \
        uv run --directory "$ai_dir/context" server.py \
        || log_warn "Could not register MCP server; register manually (see umbra-ai context/README.md)."
    else
      log_info "context-db MCP server already registered."
    fi
  else
    log_warn "claude CLI not found; register the MCP server later:"
    log_warn "  claude mcp add --scope user context-db -- uv run --directory $ai_dir/context server.py"
  fi
}

if [ "${1:-}" = "--run" ]; then
  install_ai_standard
fi
