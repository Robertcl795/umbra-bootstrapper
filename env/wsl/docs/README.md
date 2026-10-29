# Documentation

Start here. The root [README](../README.md) has the install one-liners; this
is the map of everything else.

## Find it fast

| I want to… | Go to |
| --- | --- |
| See every tool, what it replaces, and its alias | [TOOLS.md](TOOLS.md) |
| Pick or preview a prompt theme | [THEMES.md](THEMES.md) |
| Look up a command or keybinding | [CHEATSHEET.md](CHEATSHEET.md) |
| Know which file configures what | [Config map](#config-map) |
| Understand one bootstrap phase | [Phases](#bootstrap-phases) |
| Read OS-specific behaviour | [Arch](os/arch.md) · [Ubuntu](os/ubuntu.md) · [Windows](os/windows.md) |
| Fix something that broke | [Troubleshooting](CHEATSHEET.md#troubleshooting) |

## Config map

Where each piece of behaviour actually lives. Everything under `env/dot_config/`
and `env/dot_zshrc.tmpl` is deployed by chezmoi ([phase 2](sections/02-linking.md)).

| Config | Repo path | Linked to | Notes |
| --- | --- | --- | --- |
| zsh entry point | `env/dot_zshrc.tmpl` | `~/.zshrc` | Sources the modules below, in order |
| ├ history, options, completion | `env/dot_config/zsh/core.zsh` | — | `compinit` runs here |
| ├ fzf defaults + `Ctrl+F` picker | `env/dot_config/zsh/fzf.zsh` | — | |
| ├ general aliases | `env/dot_config/zsh/aliases.zsh` | — | ls / cat / grep / yazi |
| ├ **git aliases** | `env/dot_config/zsh/git.zsh` | — | [reference](CHEATSHEET.md#git) |
| ├ keybindings | `env/dot_config/zsh/bindings.zsh` | — | Registered from `zvm_after_init` |
| ├ plugins | `env/dot_config/zsh/plugins.zsh` | — | Clones into `~/.local/share/zsh/plugins` |
| ├ prompt | `env/dot_config/zsh/prompt.zsh` | — | Starship init |
| ├ dev toolchains | `env/dot_config/zsh/dev.zsh` | — | rustup / fnm / uv / pnpm / AI CLIs |
| ├ WSL helpers | `env/dot_config/zsh/wsl.zsh` | — | NTFS guard, interop aliases |
| └ greeting | `env/dot_config/zsh/greeting.zsh` | — | fastfetch, runs last |
| fish entry point | `env/dot_config/fish/config.fish.tmpl` | `~/.config/fish/config.fish` | only when fish is the chosen shell (ADR 0004) |
| fish drop-ins | `env/dot_config/fish/conf.d/` | `~/.config/fish/conf.d` | `aliases` · `git` · `greeting` · `fzf`; only with fish |
| Starship prompt | `env/.chezmoitemplates/starship/<theme>.toml` | `~/.config/starship.toml` | or `env/.chezmoitemplates/starship/` for `default` |
| fastfetch greeting | `env/dot_config/fastfetch/` | `~/.config/fastfetch` | `config.jsonc` + `logo/` |
| Neovim | `env/dot_config/nvim/` | `~/.config/nvim` | lazy.nvim |
| Zellij | `env/dot_config/zellij/config.kdl` | `~/.config/zellij/config.kdl` | |
| Git | `config/git/.gitconfig` | `~/.gitconfig` | |
| Alacritty | `config/alacritty/alacritty.toml` | `~/.config/alacritty/alacritty.toml` | |

Machine-local overrides go in `~/.zshrc.local` — sourced last, never touched
by the bootstrap.

## Bootstrap phases

Phases run in this order (chezmoi scripts in `env/.chezmoiscripts/`; [`install/run.sh`](../install/run.sh) is the fallback without chezmoi). The number
is what `log_step` prints during a run and what each `tests/NN_*.sh`
checkpoint validates.

| # | Script | What it does | Doc |
| --- | --- | --- | --- |
| 0 | `install/detect_os.sh` | OS detection, network + sudo preflight | [00](sections/00-preflight.md) |
| 1 | `install/packages/{ubuntu,arch}.sh` | System update, CLI stack | [01](sections/01-packages.md) |
| 2 | chezmoi (`install/chezmoi.sh`, `env/.chezmoiscripts/`) | Dotfiles copied into `$HOME`; phases run as scripts | [02](sections/02-linking.md) |
| 3 | `install/shell/{fish,zsh}.sh` | Shell, plugins, login shell | [03](sections/03-shell.md) |
| 4 | `install/prompt/starship.sh` | Starship + theme selection | [04](sections/04-prompt.md) |
| 5 | `install/nvim.sh` | Neovim + lazy.nvim | [05](sections/05-nvim.md) |
| 6 | `install/dev/k8s.sh` | kubectl, helm, k3d | [06](sections/06-kubernetes.md) |
| 7 | `install/zellij.sh` | Zellij multiplexer | [07](sections/07-zellij.md) |
| 8 | `install/dev/lang.sh` | rustup, fnm, uv | [08](sections/08-lang-toolchains.md) |
| 9 | `install/dev/ai.sh` | Claude Code, opencode, gh | [09](sections/09-ai-tooling.md) |
| 10 | `install/wsl.sh` | `.wslconfig`, systemd, NTFS guards | [10](sections/10-wsl.md) |
| 11 | `install/ai.sh` | AI Development Standard | [11](sections/11-ai-standard.md) |
| 12 | `install/fastfetch.sh` | Shell greeting | [12](sections/12-fastfetch.md) |
| — | `install/summary.sh` | Installed-tools summary (automatic) | [13](sections/13-summary.md) |

Every phase is idempotent and re-runnable on its own:

```bash
bash install/prompt/starship.sh --run     # just this phase (installs starship)
bash tests/04_prompt.sh                   # just this checkpoint
bash tests/99_smoke.sh                    # all checkpoints
```

## Native Windows

Deferred: not part of Umbra v0.2. The installer stays in lux-dotfiles.
No WSL involved — [os/windows.md](os/windows.md) has the full phase
breakdown (`windows/packages.ps1`, `windows/profile.ps1`,
`windows/terminal.ps1`, `windows/summary.ps1`) and the places it
deliberately differs from the WSL path.

## Also see

- [toolkit/ai-standard/README.md](../../../toolkit/ai-standard/README.md) — the AI Development Standard deployed
  by phase 11 (personal profile only).
