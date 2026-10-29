# Phase 3 — Shell setup (zsh / fish)

Scripts: [`install/shell/zsh.sh`](../../install/shell/zsh.sh),
[`install/shell/fish.sh`](../../install/shell/fish.sh)

`UM_SHELL` (`zsh` by default, or `fish`) picks which shell becomes your
login shell; both get installed either way so you can try the other.

## zsh (default)

`~/.zshrc` is a symlink to [`shells/zsh/zshrc`](../../shells/zsh/zshrc),
which does nothing but set a few environment variables and source the
modules in [`config/zsh/`](../../config/zsh) in a fixed order:

| Module | What it sets up |
| --- | --- |
| `core.zsh` | History (100k, shared, dedup), `AUTOCD`, `NUMERIC_GLOB_SORT`, `compinit`, case-insensitive completion, zoxide, system fzf bindings |
| `fzf.zsh` | `FZF_DEFAULT_*`, `bat` preview, the `Ctrl+F` picker widget |
| `aliases.zsh` | eza / bat / ripgrep / duf aliases, `y` (yazi with directory-follow), `lg`, `ld`, `ff` |
| `git.zsh` | [Git aliases](../CHEATSHEET.md#git) + their completions |
| `bindings.zsh` | Keybindings, registered from `zvm_after_init` |
| `plugins.zsh` | Plugin loader + `zplugin-update` |
| `prompt.zsh` | Starship init |
| `dev.zsh` | rustup / fnm / uv / pnpm / AI CLI paths |
| `wsl.zsh` | NTFS performance guard, interop aliases |
| `greeting.zsh` | [fastfetch banner](12-fastfetch.md) |

**Order matters** in two places: `core.zsh` runs `compinit` before `git.zsh`
registers its completions, and `bindings.zsh` runs before `plugins.zsh`
because zsh-vi-mode reads its `ZVM_*` settings at load time.

`~/.zshrc.local` is sourced after every module and is never touched by the
bootstrap — put machine-specific settings there.

### Plugins

| Plugin | Gives you |
| --- | --- |
| [zsh-vi-mode](https://github.com/jeffreytse/zsh-vi-mode) | Vi editing, cursor shape per mode |
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | Inline suggestion from history (`Ctrl+\` toggles) |
| [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting) | Command-line colouring |
| [zsh-history-substring-search](https://github.com/zsh-users/zsh-history-substring-search) | `↑`/`↓` search by prefix |

They're pre-cloned into `${XDG_DATA_HOME:-~/.local/share}/zsh/plugins` during
this phase so the first shell launch is instant and works offline;
`plugins.zsh` re-clones any that are missing. Update them all with
`zplugin-update`.

### Login shell

Set via `usermod -s` (falls back to `chsh`) — confirmed interactively unless
`UM_NONINTERACTIVE=1`, in which case it proceeds when `UM_SHELL=zsh`. The
shell is added to `/etc/shells` first, since `chsh` refuses shells missing
from it.

## fish

`~/.config/fish/config.fish` and `conf.d/` are symlinked from
[`shells/fish/`](../../shells/fish). The `conf.d` drop-ins mirror the zsh
modules: `aliases.fish`, `git.fish` (same alias names, completions inherited
via `complete -w`), `greeting.fish`, `fzf.fish`.

Runs only when fish is the chosen shell (`UM_SHELL=fish`); with the default
zsh, fish is neither installed nor linked (ADR 0004: fish is theme-only in
Umbra). When it runs, it installs [fisher](https://github.com/jorgebucaran/fisher)
as the plugin manager and `PatrickF1/fzf.fish` for fzf integration, and offers
to `chsh` to fish interactively (never in `UM_NONINTERACTIVE=1` mode; default
answer "no").

## OS notes

Both apt (Ubuntu) and pacman (Arch) package `fish`/`zsh` directly — no
release-binary fallbacks needed here, unlike phase 1. On native Windows
there's no zsh or fish at all; `windows/profile.ps1` reproduces the aliases,
history predictions and fzf bindings in pwsh instead — see
[os/windows.md](../os/windows.md).

## Customization

`UM_SHELL=fish|zsh`

## Test

[`tests/03_shell.sh`](../../tests/03_shell.sh) — non-interactive `fish -lc`
and `zsh -lic` startup must not error, the `config/zsh` modules must be
loaded (aliases, plugin loader, and every git alias the cheatsheet
documents), `compdef` must be available for the completions, the four
plugins must be on disk, and (when `UM_SHELL=zsh`) the login shell must
actually be zsh.
