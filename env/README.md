# env

- **Purpose:** dotfiles for every machine profile.
- **Status:** active for WSL (`wsl/`); `core/` and `omarchy/` planned
- **Activates in:** v0.2 for `wsl/` (migrated from lux-dotfiles); Phase 2 for the rest
- **Contains:** `wsl/`, the WSL Ubuntu/Arch bootstrapper with its configs, shells, Neovim and checkpoint tests. Entry: `wsl/bootstrap.sh`. See [wsl/README.md](wsl/README.md).
- **Will contain:** `core/` shell-agnostic config (zsh, git, starship, fzf) split out of `wsl/` when chezmoi is adopted (ADR 0003), `omarchy/` overrides on top of Omarchy without forking it.
