# Stack

What Umbra installs, how it is configured, and how to use it day to day. Each platform has its own page for what differs:

| Platform | Page | Status |
|---|---|---|
| Omarchy | [omarchy.md](omarchy.md) | supported |
| Arch and Ubuntu, native | [linux.md](linux.md) | supported |
| WSL Arch and WSL Ubuntu | [wsl.md](wsl.md) | supported |
| macOS, native Windows | [planned.md](planned.md) | Planned |

## Components

Each component is a phase. chezmoi runs them as scripts from [`env/.chezmoiscripts/`](../../env/.chezmoiscripts), and each has a checkpoint test in [`env/wsl/tests/`](../../env/wsl/tests). Select phases with `--components a,b` or `--skip c`. The dotfiles are always deployed.

| Phase | What it installs | Test |
|---|---|---|
| `packages` | `git curl wget unzip ripgrep fd bat eza fzf zoxide neovim starship tldr zsh lazygit glow duf lazydocker yazi sshs lnav just zellij fastfetch`; fish only when chosen | `01_packages.sh` |
| `shell` | zsh as login shell, with zsh-vi-mode, zsh-autosuggestions, fast-syntax-highlighting and zsh-history-substring-search pre-cloned to `~/.local/share/zsh/plugins` (`UM_SHELL=fish`: fish, fisher, fzf.fish) | `03_shell.sh` |
| `prompt` | [Starship](https://starship.rs); `~/.config/starship.toml` in the chosen variant | `04_prompt.sh` |
| `nvim` | Neovim with lazy.nvim and the Umbra colorscheme | `05_nvim.sh` |
| `k8s` | `kubectl`, `helm`, `k3d` (`UM_ENABLE_K8S=0` skips it) | `06_dev.sh` |
| `zellij` | zellij with the Umbra theme | covered by the chezmoi checks |
| `lang` | rustup, fnm (Node LTS), uv, pnpm | `07_devstack.sh` |
| `ai-cli` | Claude Code, opencode (personal only), `gh` with the Copilot extension once `gh auth login` is done | `09_ai.sh` |
| `wsl` | WSL tuning; see [wsl.md](wsl.md) | `08_wsl.sh` |
| `ai-standard` | Umbra AI's standard, when Umbra AI is installed (personal only) | `09_ai.sh` |
| `fastfetch` | the greeting on each new interactive shell | `12_fastfetch.sh` |
| `desktop` (opt-in, native only) | Ghostty and JetBrainsMono Nerd Font | container scenario `desktop` |

The run ends with a summary of installed versions, then the doctor (`99_smoke.sh`, all checkpoints). Every downloaded binary is pinned and sha256-checked.

### Configuration

Everything is interactive on a terminal. Every prompt has an environment variable, and with `--yes` or no terminal every prompt takes its default. chezmoi stores the choices in `~/.config/chezmoi/chezmoi.toml`, never in the repo.

| Variable (flag) | Values | Default |
|---|---|---|
| `UM_THEME` | `umbra`, `void`, `lux` (other names fall back to `umbra`) | `umbra` |
| `UM_SHELL` | `zsh`, `fish` | `zsh` |
| `UM_MODE` (`--profile`) | `personal`, `work`; work skips the personal-only parts | `personal` |
| `UM_COMPONENTS` (`--components`), `UM_SKIP` (`--skip`) | comma-separated phase names | all phases |
| `UM_ENABLE_K8S` | `0`, `1` | asked on a terminal; otherwise `1` |
| `UM_NONINTERACTIVE` (`--yes`) | `1` accepts every default | unset |
| `UM_NO_FASTFETCH` | `1` disables the greeting | unset |
| `UM_NO_AUTOCD` | `1` keeps shells in `/mnt/*` | unset |
| `UM_REPO_DIR`, `UM_BRANCH` | where a fresh clone goes, which branch | `~/dev/umbra-bootstrapper`, `main` |
| `UM_VERBOSE` | `1` traces every command | unset |

The WSL-only variables are on [wsl.md](wsl.md).

## Themes

One color map generates every theme file in [`themes/`](../../themes). The files here are byte-identical copies, so this repo works on its own, and CI rejects any color outside the map. There are three variants, each with text contrast of at least 4.5:1:

| Variant | Background | Use |
|---|---|---|
| `umbra` | `#0E0B1A` | default, dark |
| `void` | `#07060D` | darkest background |
| `lux` | `#F7F5FE` | light |

| App | File | Applied |
|---|---|---|
| zsh/fish colors, fzf, `BAT_THEME` | `themes/shell/colors*.zsh`, `*.fish` | automatically, in the chosen variant |
| Starship | `env/.chezmoitemplates/starship/{umbra,void,lux}.toml` | automatically |
| bat | `themes/bat/Umbra*.tmTheme` | automatically (`bat cache --build` runs on change) |
| zellij | `themes/zellij/umbra*.kdl` | automatically (`theme "umbra…"` in `config.kdl`) |
| Neovim | `themes/nvim/colors/umbra.lua` | automatically (`plugin/umbra.lua` sets the variant) |
| Ghostty (desktop) | `themes/terminals/ghostty/umbra*` | automatically |
| btop | `~/.config/btop/themes/umbra*.theme` | set `color_theme = "umbra"` in `btop.conf` |
| tmux | `~/.config/tmux/umbra*.tmux` | add `source-file ~/.config/tmux/umbra.tmux` |
| Alacritty, Kitty (desktop) | `~/.config/alacritty/themes/`, `~/.config/kitty/themes/` | `import = [...]` under `[general]`; `include themes/umbra.conf` |
| VS Code (desktop, not WSL) | `~/.vscode/extensions/umbra-theme/` | pick "Umbra", "Umbra Void" or "Umbra Lux" (loading an unpacked folder is `verify`) |
| Hyprland, Waybar (desktop, non-Omarchy) | `~/.config/hypr/umbra*.conf`, `~/.config/waybar/umbra*.css` | `source =` it from `hyprland.conf`; `@import` it from `style.css` (syntax `verify`) |

Discord, Spotify and more TUI apps are Planned.

## Day to day

### Shell

zsh loads its modules from `~/.config/zsh/` in a fixed order (core, fzf, aliases, git, bindings, plugins, prompt, dev, wsl, greeting). `~/.zshrc.local` is sourced last and never touched: machine-specific settings go there. fish has the same aliases in `conf.d/`.

| Key or command | Does |
|---|---|
| `Ctrl+R` · `Ctrl+T` · `Alt+C` | fuzzy history · file picker with preview · fuzzy cd |
| `Ctrl+F` | file picker without hidden files, inserts the path |
| `↑` / `↓` | history search by what you typed |
| `Ctrl+\` | toggle autosuggestions |
| `**<Tab>` | fzf completion anywhere |
| `Esc` | vi normal mode (the cursor shape follows the mode) |

### Aliases

| Git | | Files and tools | |
|---|---|---|---|
| `gst` · `gss` | status · short | `ls` `ll` `la` `tree` | eza with icons and git status |
| `ga` · `gaa` · `gap` | add · all · patch | `cat` | bat |
| `gc` · `gcm` · `gca` · `gcan` | commit -v · -m · amend · amend no-edit | `grep` · `fd` | ripgrep · fd |
| `gco` · `gcob` · `gsw` · `gswc` | checkout · -b · switch · -c | `z <part>` · `zi` | zoxide jump · picker |
| `gb` · `gbd` · `gbD` · `gbclean` | branch · delete · force · prune merged | `y` | yazi; quitting cds where you left |
| `gd` · `gds` · `gl` · `gadog` | diff · staged · last 20 · graph | `lg` · `ld` | lazygit · lazydocker |
| `gf` · `gpl` · `gp` · `gpu` · `gpf` | fetch --prune · pull --rebase · push · -u · --force-with-lease | `df` · `ff` · `vim` | duf · fastfetch · nvim |
| `gsta` · `gstp` · `grbi` · `gwt` | stash · pop · rebase -i · worktree | `tldr` · `glow` · `lnav` · `sshs` · `just` | examples · Markdown · logs · ssh hosts · tasks |

Git aliases complete like the command they wrap.

### Managing the environment

```sh
chezmoi diff && chezmoi apply          # after editing a dotfile in the checkout's env/
UM_THEME=void chezmoi init --apply     # switch variant
bash install.sh --yes                  # re-run everything; a second run changes nothing
bash env/wsl/install/summary.sh --run  # what is installed, with versions
zplugin-update && exec zsh             # update zsh plugins, reload
```

| Problem | Fix |
|---|---|
| Boxes instead of icons | select a Nerd Font in the terminal |
| Slow shell start | `time zsh -i -c exit`, then comment modules out of `~/.zshrc` to bisect |
| Stale completions | `rm ~/.cache/zsh/zcompdump && exec zsh` |
| A plugin failed to load | `rm -rf ~/.local/share/zsh/plugins && exec zsh` (they re-clone) |
| No greeting | it is skipped in non-interactive shells, editor terminals, `TERM=dumb`/`linux`, under 70 columns, or with `UM_NO_FASTFETCH=1` |

## Tests

- **Static checks:** `scripts/verify.sh`. Shell syntax, layout, shellcheck on the new code, guards.
- **In containers:** the Umbra umbrella runs the full bootstrap in Ubuntu 26.04 and Arch containers. Each runs twice, for the personal and work profiles, and checks every phase, the chezmoi state, writes outside `$HOME`, the variant switch, and that a second run changes nothing.
- **On real WSL:** gates on disposable WSL distros cover the fresh-root path; see [wsl.md](wsl.md).
