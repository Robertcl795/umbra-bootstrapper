# Phase 2 — Clone + link Umbra configs

Script: [`install/link.sh`](../../install/link.sh)

Symlinks repo config into place using `symlink_with_backup` (from
`install/common.sh`), which never overwrites silently: if the destination
already exists and isn't already the correct symlink, it's moved to
`<path>.backup.<timestamp>` first.

| Source | Destination |
| --- | --- |
| `shells/fish/config.fish` (fish only) | `~/.config/fish/config.fish` |
| `shells/fish/conf.d` (fish only) | `~/.config/fish/conf.d` |
| `shells/fish/functions` (fish only) | `~/.config/fish/functions` |
| `shells/zsh/zshrc` | `~/.zshrc` |
| `shells/zsh` | `~/.config/zsh` |
| `nvim` | `~/.config/nvim` |
| `config/fastfetch` | `~/.config/fastfetch` |

`~/.config/starship.toml` is linked separately in
[phase 4](04-prompt.md), since which file it points at depends on
`UM_THEME`.

Re-running the bootstrap is safe: if the symlink already points at the
repo, `symlink_with_backup` is a no-op; nothing is re-backed-up on every
run.

## OS notes

Symlinks work the same way on Ubuntu and Arch (same filesystem semantics
under WSL). There is no equivalent phase on native Windows — creating
real symlinks there needs admin rights or Developer Mode, so
`windows/profile.ps1` points `$env:STARSHIP_CONFIG` and friends directly at
files inside the cloned repo instead of symlinking; see
[os/windows.md](../os/windows.md).

## Test

[`tests/02_linking.sh`](../../tests/02_linking.sh) checks each destination
resolves back into the repo.
