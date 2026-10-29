# Phase 4 — Prompt themes (Starship)

Script: [`install/prompt/starship.sh`](../../install/prompt/starship.sh)

Installs [Starship](https://starship.rs) if it isn't already on `PATH`
(official installer script). `~/.config/starship.toml` is rendered by chezmoi
from `env/.chezmoitemplates/starship/<theme>.toml`, using the stored `theme` value
(ADR 0006).

## Themes

`UM_THEME` picks one of five. Previews, palettes and Nerd Font
requirements: **[THEMES.md](../THEMES.md)**.

| Theme | Accent | File | Nerd Font |
| --- | --- | --- | --- |
| `default` | green, two-line box | `env/.chezmoitemplates/starship/default.toml` | yes |
| `tron` | electric cyan | `env/.chezmoitemplates/starship/tron.toml` | no |
| `cyber` | terminal green | `env/.chezmoitemplates/starship/cyber.toml` | no |
| `eva01` | violet | `env/.chezmoitemplates/starship/eva01.toml` | no |
| `minimal` | blue/purple, single line | `env/.chezmoitemplates/starship/minimal.toml` | yes |

`default` is the interactive default on the WSL path; the native-Windows
path defaults to `cyber` (it's the only one of the two with a matching
terminal colour scheme). Falls back to the default config with a warning if
`UM_THEME` doesn't match a `themes/*` directory.

Switch themes any time without re-running the whole bootstrap:

```bash
UM_THEME=tron chezmoi init --apply
# same thing:
UM_THEME=tron chezmoi init --apply
```

## OS notes

Identical on Ubuntu and Arch — starship itself is a single static binary,
no OS-specific packaging quirks. On native Windows, the *same*
`env/.chezmoitemplates/starship/<theme>.toml` files are reused (via `$env:STARSHIP_CONFIG`
rather than a symlink) — see [os/windows.md](../os/windows.md) — plus each
theme also has a matching `env/.chezmoitemplates/starship/` color
scheme for the terminal itself, which has no bash-side equivalent.

## Test

[`tests/04_prompt.sh`](../../tests/04_prompt.sh) runs `starship prompt`
non-interactively and checks it exits 0.
