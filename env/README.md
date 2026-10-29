# env

- **Purpose:** dotfiles for every machine profile.
- **Status:** active for WSL Ubuntu and WSL Arch; Omarchy planned (managed by nothing yet)
- **Activates in:** v0.2 for WSL; chezmoi since ADR 0006; Omarchy after its plan (Stage 7b)
- **Contains:** the chezmoi source (the repo's `.chezmoiroot` points here) and `wsl/`, the bootstrapper. Entry: `bash env/wsl/bootstrap.sh`; see [wsl/README.md](wsl/README.md).

| Path | What it holds |
|---|---|
| `dot_zshrc.tmpl`, `dot_config/` | dotfiles chezmoi copies into `$HOME` (zsh modules, Neovim, fastfetch, zellij, starship, fish when chosen) |
| `.chezmoi.toml.tmpl` | the local config: `os`, `profile`, `shell`, `theme` and the phase selection, stored in `~/.config/chezmoi/chezmoi.toml` |
| `.chezmoiscripts/` | the install phases, run by chezmoi when a phase script or the selection changes |
| `.chezmoitemplates/` | starship themes, the shared script header |
| `.chezmoiignore` | source-only folders; fish unless chosen; everything on Omarchy for now |
| `wsl/` | `bootstrap.sh`, the phase scripts, pinned checksums, checkpoint tests, docs |
| `core/`, `omarchy/` | reserved (ignored by chezmoi) |

## Day to day

```sh
chezmoi diff && chezmoi apply          # after editing a file in env/
UM_THEME=tron chezmoi init --apply     # switch the prompt theme
bash env/wsl/bootstrap.sh --yes        # re-run everything that changed
```

## From v0.2.0 (one-time switch)

The first apply removes the v0.2.0 symlinks that point into the checkout and backs up any other existing target to `<path>.backup.<timestamp>`. Nothing else in `$HOME` is touched.

## Rollback to v0.2.0

```sh
chezmoi managed --path-style absolute   # the files chezmoi wrote; remove them
chezmoi purge                           # chezmoi's own config and state
git -C ~/dev/umbra checkout v0.2.0
bash ~/dev/umbra/env/wsl/install/link.sh --run
```
