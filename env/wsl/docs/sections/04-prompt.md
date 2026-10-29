# Phase 4 — Prompt themes (Starship)

Script: [`install/prompt/starship.sh`](../../install/prompt/starship.sh)

Installs [Starship](https://starship.rs) if it isn't already on `PATH`
(official installer script), then symlinks
`themes/<UM_THEME>/starship.toml` to `~/.config/starship.toml` with a
timestamped backup of anything already there.

## Themes

`UM_THEME` picks one of five. Previews, palettes and Nerd Font
requirements: **[THEMES.md](../THEMES.md)**.

| Theme | Accent | File | Nerd Font |
| --- | --- | --- | --- |
| `default` | green, two-line box | `config/starship/starship.toml` | yes |
| `tron` | electric cyan | `themes/tron/starship.toml` | no |
| `cyber` | terminal green | `themes/cyber/starship.toml` | no |
| `eva01` | violet | `themes/eva01/starship.toml` | no |
| `minimal` | blue/purple, single line | `themes/minimal/starship.toml` | yes |

`default` is the interactive default on the WSL path; the native-Windows
path defaults to `cyber` (it's the only one of the two with a matching
terminal colour scheme). Falls back to the default config with a warning if
`UM_THEME` doesn't match a `themes/*` directory.

Switch themes any time without re-running the whole bootstrap:

```bash
UM_THEME=tron bash install/prompt/starship.sh --run
# same thing:
UM_THEME=tron bash install/prompt/starship.sh --run
```

## OS notes

Identical on Ubuntu and Arch — starship itself is a single static binary,
no OS-specific packaging quirks. On native Windows, the *same*
`themes/<name>/starship.toml` files are reused (via `$env:STARSHIP_CONFIG`
rather than a symlink) — see [os/windows.md](../os/windows.md) — plus each
theme also has a matching `themes/<name>/windows-terminal.json` color
scheme for the terminal itself, which has no bash-side equivalent.

## Test

[`tests/04_prompt.sh`](../../tests/04_prompt.sh) runs `starship prompt`
non-interactively and checks it exits 0.
