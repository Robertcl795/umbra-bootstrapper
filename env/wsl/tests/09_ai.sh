#!/usr/bin/env bash
set -euo pipefail

# AI development standard (ai/): structure, deployment and context DB env.

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
# The AI standard lives in the umbra repo's toolkit/ (three levels above env/wsl/tests).
AI_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)/toolkit/ai-standard"

# Personal-only (ADR 0007, decision 11).
if [ "${UM_MODE:-personal}" = "work" ]; then
  echo "Work profile: AI standard not installed; skipped." >&2
  exit 0
fi

# Canonical structure
for f in \
  "$AI_DIR/README.md" \
  "$AI_DIR/scaffold.sh" \
  "$AI_DIR/justfile" \
  "$AI_DIR/instructions/components.instructions.md" \
  "$AI_DIR/instructions/html.instructions.md" \
  "$AI_DIR/instructions/scss.instructions.md" \
  "$AI_DIR/instructions/util.instructions.md" \
  "$AI_DIR/agents/angular-reviewer.md" \
  "$AI_DIR/agents/security-auditor.md" \
  "$AI_DIR/agents/test-writer.md" \
  "$AI_DIR/agents/planner.md" \
  "$AI_DIR/prompts/angular-review.md" \
  "$AI_DIR/skills/angular-standards/SKILL.md" \
  "$AI_DIR/skills/context-db/SKILL.md" \
  "$AI_DIR/context/pyproject.toml" \
  "$AI_DIR/context/indexer.py" \
  "$AI_DIR/context/server.py"
do
  [ -f "$f" ] || { echo "Missing: $f" >&2; exit 1; }
done

# Python sources must at least be syntactically valid
if command -v python3 >/dev/null 2>&1; then
  python3 -m py_compile "$AI_DIR/context/indexer.py" "$AI_DIR/context/server.py"
fi

# Global deployment (only checked if install/ai.sh has run)
if [ -d "$HOME/.claude/agents" ]; then
  [ -e "$HOME/.claude/agents/angular-reviewer.md" ] \
    || { echo "Agents not linked into ~/.claude/agents." >&2; exit 1; }
fi

# Context DB env + a real index/search round-trip. The first run downloads
# the embedding model; on restricted networks that fails, so a failed index
# is a warning — but a successful index with irrelevant search results is
# a hard failure.
export PATH="$HOME/.local/bin:$PATH"
if command -v uv >/dev/null 2>&1 && [ -d "$AI_DIR/context/.venv" ]; then
  if uv run --directory "$AI_DIR/context" indexer.py index --repo "$AI_DIR/../.." --collection umbra-smoke >/dev/null 2>&1; then
    uv run --directory "$AI_DIR/context" indexer.py search "zellij multiplexer" --collection umbra-smoke \
      | grep -qi "zellij" || { echo "Context DB search returned nothing relevant." >&2; exit 1; }
    echo "Context DB round-trip OK." >&2
  else
    echo "[warn] Context DB indexing failed (embedding model download blocked?); skipped round-trip." >&2
  fi
else
  echo "[warn] uv env not ready; skipped context DB round-trip." >&2
fi

echo "AI standard OK."
