# Phase 12 — Shell greeting (fastfetch)

Script: [`install/fastfetch.sh`](../../install/fastfetch.sh)

Installs [fastfetch](https://github.com/fastfetch-cli/fastfetch) and turns it
into the banner every new interactive shell opens with — new tab, new window,
new zellij pane.

## What runs where

| Shell | Hook | File |
| --- | --- | --- |
| zsh | Sourced last from `~/.zshrc` | [`env/dot_config/zsh/greeting.zsh`](../../../dot_config/zsh/greeting.zsh) |
| fish | Overrides `fish_greeting` | [`env/dot_config/fish/conf.d/greeting.fish`](../../../dot_config/fish/conf.d/greeting.fish) |
| pwsh | Tail of the managed profile block | [`windows/profile.ps1`](https://github.com/Robertcl795/dotfiles/blob/1b1239a/windows/profile.ps1) |

The greeting is deliberately the *last* thing the shell config does, so it
renders below anything the modules before it print (WSL warnings, plugin
install messages).

## When it stays quiet

The banner is skipped — silently, never with an error — when any of these
hold:

| Condition | Why |
| --- | --- |
| `UM_NO_FASTFETCH` is set | Explicit opt-out |
| The shell isn't interactive | Scripts and `ssh host cmd` shouldn't print a banner |
| stdout isn't a TTY | Output is being piped or captured |
| `fastfetch` isn't on `PATH` | Partial install must never break shell startup |
| `$NVIM` / `$VIM` is set | Editor terminals |
| `TERM` is `dumb` or `linux` | No Nerd Font glyphs there |
| Terminal is under 70 columns | Logo and info block stop fitting side by side — falls back to `--logo none` rather than wrapping into a mess |

```bash
export UM_NO_FASTFETCH=1     # in ~/.zshrc.local — permanent
UM_NO_FASTFETCH=1 zsh        # one shell
```

## Config

[`env/dot_config/fastfetch/config.jsonc`](../../../dot_config/fastfetch/config.jsonc),
symlinked to `~/.config/fastfetch` in [phase 2](02-linking.md).

Modules: OS, kernel, uptime, package count, shell, terminal — then CPU, RAM,
disk — then a colour bar. Keys are cyan, the title is magenta, and the whole
thing is padded to a fixed key width so the values line up.

It runs on every new tab, so it stays cheap: no `command` modules (each one
forks a process), nothing network-backed.

## Logo

Two options, one line apart in the config:

| Logo | Config |
| --- | --- |
| Distro built-in (**current**) | `"logo": { "type": "builtin" }` |
| Custom Arch mark with `RL` initials | `"logo": { "type": "file", "source": "~/.config/fastfetch/logo/arch-rl.txt", "color": { "1": "cyan", "2": "magenta" } }` |

The custom mark lives at
[`env/dot_config/fastfetch/logo/arch-rl.txt`](../../../dot_config/fastfetch/logo/arch-rl.txt):
a 21×45 block-drawn Arch triangle with the initials punched into the hollow,
`$1`/`$2` colour placeholders splitting it into a cyan frame and magenta
letters. `~` is expanded by fastfetch itself, so the same config works on
Linux and Windows.

Any `.txt` in `env/dot_config/fastfetch/logo/` can be used the same way — pass
`--logo-type file` on the command line to preview one without editing the
config.

## OS notes

| OS | Source |
| --- | --- |
| Arch | `pacman -S fastfetch` (official repos) |
| Ubuntu | `apt` from 24.10 onwards; older releases (including the LTS) get the upstream release tarball into `~/.local/bin` |
| Windows | `scoop install fastfetch`, and `Set-FastfetchConfig` junctions `config\fastfetch` into `~\.config\fastfetch` (a junction needs no admin rights, unlike a symlink; it falls back to a copy) |

## Customization

`UM_NO_FASTFETCH=1` disables the greeting. Everything else is
`env/dot_config/fastfetch/config.jsonc` — see the
[fastfetch configuration wiki](https://github.com/fastfetch-cli/fastfetch/wiki/Configuration)
for the full module list.

Re-run this phase alone after editing:

```bash
bash install/fastfetch.sh --run
```

## Test

[`tests/12_fastfetch.sh`](../../tests/12_fastfetch.sh) — the binary is on
`PATH`, `~/.config/fastfetch/config.jsonc` resolves, `fastfetch --pipe`
renders with an empty stderr (which catches a bad `config.jsonc` or a logo
file the config points at but that isn't there), and `UM_NO_FASTFETCH=1`
doesn't break shell startup.
