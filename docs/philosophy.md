# Philosophy

*Dark by default. Sharp by design.*

Umbra layers on top of your Linux. It is not a distro, a cloud service or an agent framework. These rules decide what goes in and how it behaves.

## Opinionated defaults, with exits

Every choice has a default that works without questions: zsh, Starship, Neovim, zellij, the umbra variant. Every default also has an exit:
- a menu item you can untick;
- an environment variable (`UM_SHELL=fish`, `UM_THEME=lux`, `UM_ENABLE_K8S=0`);
- `--skip`;
- `~/.zshrc.local` for anything machine-specific.

Re-running is safe: a second run changes nothing.

## Layers that stand alone

The environment, the themes and the AI layer each work without the others. This bootstrapper runs without any other Umbra repo, and the Omarchy theme installs without the bootstrapper. On Omarchy, Omarchy owns its defaults: Umbra adds zsh, Starship and missing tools, and never replaces Omarchy's editor, terminal, fonts or updates.

## Personal and work modes

There are two profiles, and the boundary between them is strict:

| | personal | work |
|---|---|---|
| AI tools | your own accounts and local models | only the tools company policy allows (the company's Copilot and Claude Code, offline local models); a personal AI account is never used |
| Vault | read and write | reads only `work-readable/`; writes only tasks and habits |
| Integrations | as you choose | no external MCP servers, no personal accounts |

Work mode limits what Umbra does. It does not replace your company's rules: check them before you install anything on a work machine. A work-only WSL instance keeps the separation simple.

## Privacy by structure

Private material is kept out by where things live, not by trusting yourself to be careful:
- The vault is its own private repo, never a submodule of a public one.
- A pre-commit hook blocks vault paths and key files.
- Generated files carry no personal data.
- Scanners print findings masked.

## Dependencies only when needed, each with an exit path

A new tool needs a reason and a way out. Downloads are pinned and sha256-checked. Generators and checks use the python3 standard library and shell. Optional tools fall back to something plain when absent: without gum, use the `--yes` flags; without zellij or nvim, the theme checks fall back to a pattern check.

## Approval gates and evidence

Work runs as plan → approve → execute. A change is done when its evidence exists:
- a test that failed before the fix and passes after it;
- the commands and their results recorded;
- known failures kept as a baseline instead of being re-discovered.

The agent never decides alone: every decision traces back to a requirement.

## One palette

Every color of every theme comes from one map. CI fails on any other value, and on contrast below WCAG AA for text. The three variants share roles, so a fix in the map reaches every app.
