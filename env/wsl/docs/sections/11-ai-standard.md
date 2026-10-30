# Phase 11 — AI Development Standard

Script: [`install/ai.sh`](../../install/ai.sh) — full docs:
`ai/README.md` (private umbra-ai repo: `toolkit/ai-standard/README.md`)

Deploys this repo's `ai/` (private umbra-ai repo: `toolkit/ai-standard`) directory globally so it's available
in every project, not just this one:

| Source | Destination |
| --- | --- |
| `ai/agents/*.md` | `~/.claude/agents/` (Claude Code subagents) |
| `ai/prompts/*.md` | `~/.claude/commands/` (slash commands) |
| `ai/skills/*/` | `~/.claude/skills/` |

All via `symlink_with_backup`, so edits to `ai/` in the repo show up
immediately everywhere without re-running the bootstrap.

It also sets up the local vector context DB (ChromaDB + fastembed, under
`ai/context/`): runs `uv sync` in that directory, then registers it as an
MCP server with Claude Code (`claude mcp add --scope user context-db`) if
not already registered. Both steps are skipped with a warning (not a
failure) if `uv`/`claude` aren't on `PATH` yet — re-run this phase alone
after phase 8/9 finish:

```bash
bash install/ai.sh --run
```

To scaffold this same standard into an arbitrary project (not just deploy
it globally), see `bash toolkit/ai-standard/scaffold.sh /path/to/repo` (from the umbra checkout)
(`ai/scaffold.sh` (private umbra-ai repo: `toolkit/ai-standard/scaffold.sh`)).

## OS notes

Identical on Ubuntu and Arch (symlinks + `uv`/`claude`, no OS-specific
branching). Not currently ported to the native Windows path — Claude Code
itself installs there (see [os/windows.md](../os/windows.md)), but the
`ai/` agents/prompts/skills/context-DB deployment is WSL/bash-only for now.

## Test

[`tests/09_ai.sh`](../../tests/09_ai.sh) checks the canonical `ai/`
structure exists, byte-compiles the Python context-DB sources, checks the
global symlinks if phase 11 has run, and — if the `uv` env is ready — does
a real index+search round-trip against the repo itself.
