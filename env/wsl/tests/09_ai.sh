#!/usr/bin/env bash
set -euo pipefail

# AI-Standard (umbra-ai, ADR 0028 in the umbrella): structure, `um ai setup` links, context DB env.

SOURCE_PATH="${BASH_SOURCE[0]:-${0:-}}"
SCRIPT_DIR="$(cd -- "$(dirname "$SOURCE_PATH")" && pwd)"
# The AI-Standard lives in the umbra-ai repo (ADR 0018); same lookup as install/ai.sh.
UM_ENV_DIR="${UM_ENV_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
# shellcheck disable=SC1091
source "$UM_ENV_DIR/install/common.sh"
AI_DIR="$(find_ai_standard)" || { echo "AI-Standard not found (set UM_AI_DIR)" >&2; exit 1; }

# Canonical structure
for f in \
  "$AI_DIR/standard/manifest.toml" \
  "$AI_DIR/standard/global/safety.md" \
  "$AI_DIR/tools/umbra_ai.py" \
  "$AI_DIR/tools/generate.py" \
  "$AI_DIR/tools/check.py" \
  "$AI_DIR/profiles/profiles.toml" \
  "$AI_DIR/routing/rules.toml" \
  "$AI_DIR/adapters/claude/rules/umbra-global.md" \
  "$AI_DIR/adapters/copilot/copilot-instructions.md" \
  "$AI_DIR/adapters/agy/rules/umbra-global.md" \
  "$AI_DIR/context/pyproject.toml" \
  "$AI_DIR/context/indexer.py" \
  "$AI_DIR/context/server.py"
do
  [ -f "$f" ] || { echo "Missing: $f" >&2; exit 1; }
done

if command -v python3 >/dev/null 2>&1; then
  python3 -m py_compile "$AI_DIR/tools/umbra_ai.py" "$AI_DIR/context/indexer.py" "$AI_DIR/context/server.py"
  python3 -I "$AI_DIR/tools/check.py" all >/dev/null || { echo "AI-Standard checks failed: python3 -I $AI_DIR/tools/check.py" >&2; exit 1; }
fi

# Global layer (only checked once install/ai.sh has run)
if [ -d "$HOME/.claude/rules" ]; then
  [ -L "$HOME/.claude/rules/umbra-global.md" ] \
    || { echo "AI-Standard not linked into ~/.claude/rules (um ai setup)." >&2; exit 1; }
fi

if [ "${UM_MODE:-personal}" = "work" ]; then
  if grep -q '"context-db"' "$HOME/.claude.json" 2>/dev/null; then
    echo "Work profile: an MCP server is registered (ADR 0007)." >&2
    exit 1
  fi
  echo "AI-Standard OK (work)."
  exit 0
fi

# Context DB env + a real index/search round-trip over the bootstrapper repo (its docs cover
# zellij). The first run downloads the embedding model; on restricted networks that fails, so a
# failed index is a warning, but a successful index with irrelevant results is a hard failure.
export PATH="$HOME/.local/bin:$PATH"
if command -v uv >/dev/null 2>&1 && [ -d "$AI_DIR/context/.venv" ]; then
  if uv run --directory "$AI_DIR/context" indexer.py index --repo "$UM_ENV_DIR/../.." --collection umbra-smoke >/dev/null 2>&1; then
    uv run --directory "$AI_DIR/context" indexer.py search "zellij multiplexer" --collection umbra-smoke \
      | grep -qi "zellij" || { echo "Context DB search returned nothing relevant." >&2; exit 1; }
    echo "Context DB round-trip OK." >&2
  else
    echo "[warn] Context DB indexing failed (embedding model download blocked?); skipped round-trip." >&2
  fi
else
  echo "[warn] uv env not ready; skipped context DB round-trip." >&2
fi

echo "AI-Standard OK."
