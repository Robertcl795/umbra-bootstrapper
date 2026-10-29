# Tools

Every tool the bootstrap installs, what it replaces, and how to reach it.
Installed by [phase 1](sections/01-packages.md) unless noted; verify the lot
with `tests/01_packages.sh` or `bash install/summary.sh --run`.

## Modern CLI stack

| Tool | Replaces | Alias / entry | Why |
| --- | --- | --- | --- |
| [eza](https://github.com/eza-community/eza) | `ls` | `ls` `ll` `la` `tree` | Icons, git status per file, tree mode |
| [bat](https://github.com/sharkdp/bat) | `cat` | `cat`, also `$MANPAGER` | Syntax highlighting, paging, line numbers |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | `grep` | `grep` | Orders of magnitude faster, respects `.gitignore` |
| [fd](https://github.com/sharkdp/fd) | `find` | `fd` | Sane defaults, fast, gitignore-aware |
| [fzf](https://github.com/junegunn/fzf) | — | `Ctrl+R` `Ctrl+T` `Ctrl+F` `**<Tab>` | Fuzzy finder wired into history, files, completion |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | `cd` | `z <part>` `zi` | Jumps to directories you actually use |
| [duf](https://github.com/muesli/duf) | `df` | `df` | Readable disk usage |
| [yazi](https://github.com/sxyazi/yazi) | ranger / lf | `y` (also `lf`) | TUI file manager; quitting `cd`s you to where you left off |
| [lazygit](https://github.com/jesseduffield/lazygit) | — | `lg` | Full git TUI: stage hunks, rebase, cherry-pick |
| [lazydocker](https://github.com/jesseduffield/lazydocker) | — | `ld` | Container/logs/stats TUI |
| [glow](https://github.com/charmbracelet/glow) | — | `glow FILE.md` | Renders Markdown in the terminal |
| [lnav](https://lnav.org) | `tail -f` | `lnav FILE` | Log navigator with parsing and filters |
| [sshs](https://github.com/quantumsheep/sshs) | — | `sshs` | Fuzzy picker over your `~/.ssh/config` hosts |
| [just](https://github.com/casey/just) | `make` (for tasks) | `just` | Task runner; `justfile` per project |
| [zellij](https://zellij.dev) | tmux | `zellij` | Multiplexer — [config](sections/07-zellij.md) |
| [tldr](https://tldr.sh) | `man` | `tldr CMD` | Example-first help |
| [fastfetch](https://github.com/fastfetch-cli/fastfetch) | neofetch | `ff`, auto on new tabs | Greeting — [phase 12](sections/12-fastfetch.md) |

## Shell & prompt

| Tool | Role | Docs |
| --- | --- | --- |
| [zsh](https://www.zsh.org) | Default login shell | [03-shell](sections/03-shell.md) |
| [fish](https://fishshell.com) | Alternative shell (`UM_SHELL=fish`) | [03-shell](sections/03-shell.md) |
| [starship](https://starship.rs) | Prompt, 5 themes | [THEMES](THEMES.md) |
| [zsh-vi-mode](https://github.com/jeffreytse/zsh-vi-mode) | Vi editing with a usable escape story | [03-shell](sections/03-shell.md) |
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | Inline history suggestion (`Ctrl+\` toggles) | [03-shell](sections/03-shell.md) |
| [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting) | Command-line syntax colouring | [03-shell](sections/03-shell.md) |
| [zsh-history-substring-search](https://github.com/zsh-users/zsh-history-substring-search) | `↑`/`↓` search by what you typed | [03-shell](sections/03-shell.md) |
| [fisher](https://github.com/jorgebucaran/fisher) + [fzf.fish](https://github.com/PatrickF1/fzf.fish) | fish plugin manager + fzf bindings | [03-shell](sections/03-shell.md) |

zsh plugins are pre-cloned into `~/.local/share/zsh/plugins` so the first
launch is instant and works offline. Update them with `zplugin-update`.

## Editor

| Tool | Role | Docs |
| --- | --- | --- |
| [Neovim](https://neovim.io) | `$EDITOR`, `$VISUAL`, aliased to `vim` | [05-nvim](sections/05-nvim.md) |
| [lazy.nvim](https://github.com/folke/lazy.nvim) | Plugin manager, bootstraps itself on first run | [05-nvim](sections/05-nvim.md) |

## Language toolchains

| Tool | Manages | Entry | Docs |
| --- | --- | --- | --- |
| [rustup](https://rustup.rs) | Rust toolchains | `rustup show`, `cargo` | [08](sections/08-lang-toolchains.md) |
| [fnm](https://github.com/Schniz/fnm) | Node.js versions | `fnm install --lts`, auto-switches on `cd` | [08](sections/08-lang-toolchains.md) |
| [uv](https://github.com/astral-sh/uv) | Python envs + packages | `uv venv`, `uv pip` | [08](sections/08-lang-toolchains.md) |
| pnpm | Node packages | `pnpm` (standalone, no corepack) | [08](sections/08-lang-toolchains.md) |

## Kubernetes (opt-in, `UM_ENABLE_K8S=1`)

| Tool | Role | Docs |
| --- | --- | --- |
| kubectl | Cluster CLI | [06-kubernetes](sections/06-kubernetes.md) |
| helm | Chart package manager | [06-kubernetes](sections/06-kubernetes.md) |
| [k3d](https://k3d.io) | Local k3s clusters in Docker | [06-kubernetes](sections/06-kubernetes.md) |

## AI tooling

| Tool | Role | Docs |
| --- | --- | --- |
| [Claude Code](https://claude.com/claude-code) | Agentic CLI (`claude`) | [09-ai-tooling](sections/09-ai-tooling.md) |
| [opencode](https://opencode.ai) | Open-source coding agent | [09-ai-tooling](sections/09-ai-tooling.md) |
| [gh](https://cli.github.com) + copilot | GitHub CLI, `gh copilot suggest` | [09-ai-tooling](sections/09-ai-tooling.md) |
| AI Development Standard | Agents, prompts, skills, vector context DB | [11-ai-standard](sections/11-ai-standard.md) · [ai/README](../../../toolkit/ai-standard/README.md) |

## Where a tool comes from

| OS | Source | Fallback |
| --- | --- | --- |
| Arch | `pacman` (nearly everything, including `fastfetch`, `zellij`, `yazi`) | AUR via `yay` → `cargo` → GitHub release binary (`sshs`) |
| Ubuntu | `apt` | GitHub release binaries into `~/.local/bin` (`lazygit`, `glow`, `lazydocker`, `zellij`, `yazi`, `sshs`, `fastfetch`, sometimes `duf`) |
| Windows | `scoop` (`extras`/`versions` buckets) | Release zip into `%USERPROFILE%\.local\bin` (`sshs`) |

Ubuntu also normalises alternate package names — `fdfind`→`fd`,
`batcat`→`bat`, `exa`→`eza` — by symlinking the canonical name into
`~/.local/bin`. Pin release-binary versions with `UM_LAZYGIT_VERSION`,
`UM_GLOW_VERSION`, `UM_LAZYDOCKER_VERSION`, `UM_DUF_VERSION`.
