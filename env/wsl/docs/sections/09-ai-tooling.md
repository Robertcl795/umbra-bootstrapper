# Phase 9 — AI tooling (claude / opencode / gh copilot)

Script: [`install/dev/ai.sh`](../../install/dev/ai.sh)

Installs three separate AI CLIs. Every step is best-effort: a failure logs
a warning with the retry command and lets the rest of the bootstrap
continue, it never aborts the run.

- **[Claude Code](https://claude.ai)** — native installer
  (`curl -fsSL https://claude.ai/install.sh | bash`).
- **[opencode](https://opencode.ai)** — native installer
  (`curl -fsSL https://opencode.ai/install | bash`).
- **GitHub Copilot CLI** — installs `gh` (GitHub CLI) via the OS package
  manager if missing, then `gh extension install github/gh-copilot` *only
  if* `gh auth status` shows you're already logged in. If you're not
  authenticated yet, it prints the extension-install command for you to
  run manually after `gh auth login`.

This is a different thing from **phase 11** (`install/ai.sh`), which
deploys this repo's own AI Development Standard (agents/prompts/skills/
context DB) — see [11-ai-standard.md](11-ai-standard.md).

## OS notes

`gh` comes from `pacman` (`github-cli`) on Arch or `apt-get` (`gh`) on
Ubuntu; Claude Code and opencode use the same upstream installer script on
both.

## Test

Covered together with phase 8 by
[`tests/07_devstack.sh`](../../tests/07_devstack.sh): requires `claude`,
`opencode`, and `gh` on `PATH`, and warns (non-fatally) if the
`gh-copilot` extension isn't installed yet.
