# Phase 2 — Dotfiles deployed by chezmoi

Since ADR 0006 there is no linking phase. `bootstrap.sh` installs chezmoi
([`install/chezmoi.sh`](../../install/chezmoi.sh)) and runs
`chezmoi init --apply --source <checkout>`. chezmoi copies the dotfiles from
[`env/`](../../..) (the repo's `.chezmoiroot`) into `$HOME` and runs the install
phases as scripts in `env/.chezmoiscripts/`.

| Source (in `env/`) | Destination |
| --- | --- |
| `dot_zshrc.tmpl` | `~/.zshrc` |
| `dot_config/zsh/*.zsh` | `~/.config/zsh/` |
| `dot_config/nvim/` | `~/.config/nvim` |
| `dot_config/fastfetch/` | `~/.config/fastfetch` |
| `dot_config/zellij/config.kdl` | `~/.config/zellij/config.kdl` |
| `dot_config/starship.toml.tmpl` (theme from `.chezmoitemplates/starship/`) | `~/.config/starship.toml` |
| `dot_config/fish/` (fish only, ADR 0004) | `~/.config/fish/` |

The choices (profile, shell, theme, phases) are stored once in
`~/.config/chezmoi/chezmoi.toml`, never in the repo.

Day to day: edit the file in the checkout, then `chezmoi diff` and
`chezmoi apply`. Switch theme: `UM_THEME=tron chezmoi init --apply`.

First apply on a machine set up with v0.2.0: a one-time script removes the old
symlinks into the checkout and backs up any other existing file to
`<path>.backup.<timestamp>`. Rollback steps are in [env/README.md](../../../README.md).

Checkpoint: [`tests/02_linking.sh`](../../tests/02_linking.sh) — the targets are
chezmoi-managed files and `chezmoi verify` passes.
