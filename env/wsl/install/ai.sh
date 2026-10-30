#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH="$PWD"
fi
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Deploy the AI development standard (toolkit/ai-standard/) globally:
#   agents  -> ~/.claude/agents/     (Claude Code subagents)
#   prompts -> ~/.claude/commands/   (slash commands)
#   skills  -> ~/.claude/skills/     (Claude skills)
# plus: uv environment for the vector context DB and MCP registration.

install_ai_standard() {
  log_step "Phase 11: AI development standard"

  # Personal-only (ADR 0007, decision 11).
  if [ "${UM_MODE:-personal}" = "work" ]; then
    log_info "Work profile: the AI standard is personal-only; skipping."
    return 0
  fi

  # The standard lives in the private umbra-ai repo (ADR 0014, 0018).
  local ai_dir
  ai_dir="$(find_ai_standard)" || {
    log_warn "AI standard not found (umbra-ai is private: set UM_AI_DIR or clone it); skipping."
    return 0
  }

  local f name
  for f in "$ai_dir"/agents/*.md; do
    [ -e "$f" ] || continue
    symlink_with_backup "$f" "$HOME/.claude/agents/$(basename "$f")"
  done
  for f in "$ai_dir"/prompts/*.md; do
    [ -e "$f" ] || continue
    symlink_with_backup "$f" "$HOME/.claude/commands/$(basename "$f")"
  done
  for f in "$ai_dir"/skills/*/; do
    [ -d "$f" ] || continue
    name="$(basename "$f")"
    symlink_with_backup "${f%/}" "$HOME/.claude/skills/$name"
  done
  log_info "Agents, prompts and skills linked into ~/.claude."

  # Vector context DB environment (uv is installed by install/dev/lang.sh)
  export PATH="$HOME/.local/bin:$PATH"
  if ensure_cmd uv; then
    log_info "Syncing vector context DB environment (uv)..."
    (cd "$ai_dir/context" && uv sync) || log_warn "uv sync failed; run manually: uv sync (in toolkit/ai-standard/context)."
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
        || log_warn "Could not register MCP server; register manually (see toolkit/ai-standard/README.md)."
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
