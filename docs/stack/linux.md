# Arch and Ubuntu (native)

Arch Linux and Ubuntu 26.04 on real hardware or a VM. You get every component from the [stack overview](README.md), except WSL tuning, plus an optional desktop component.

## What Umbra installs

- Every phase except `wsl`: packages, shell, prompt, Neovim, Kubernetes tools, zellij, language toolchains, AI CLIs, fastfetch.
- **`desktop`** (pre-selected when a desktop session runs): Ghostty and JetBrainsMono Nerd Font.
  - Arch: `pacman -S --needed ghostty ttf-jetbrains-mono-nerd`.
  - Ubuntu: Ghostty from apt when the archive has it, otherwise a pinned, sha256-checked `.deb`. The font comes from a pinned, checked nerd-fonts release, into `~/.local/share/fonts/umbra/`.
- Never touched: the display manager, desktop environment settings, `/etc`, system fonts, the default-terminal setting, other terminals' configs.

Package sources:

| | Arch | Ubuntu |
|---|---|---|
| Most tools | `pacman` (official repos, including zellij, yazi, fastfetch, starship) | `apt` |
| Exceptions | `sshs`: AUR via `yay`, then `cargo install`, then a release binary | `lazygit`, `glow`, `lazydocker`, `zellij`, `yazi`, `sshs` (and `duf` when apt lacks it) as pinned release binaries in `~/.local/bin`; `fdfind`, `batcat`, `exa` linked to their usual names; Starship into `~/.local/bin` |

## How themes apply

As in the [overview](README.md#themes). With `desktop`, Ghostty uses the chosen variant, and the Alacritty, Kitty, VS Code, Hyprland and Waybar theme files are deployed for you to enable.

## Known limits

- Rendering on a real desktop is a manual check (`desktop-ubuntu`, `desktop-arch`).
- VS Code loading the theme from an unpacked folder, tmux hex colours, and the Hyprland and Waybar syntax are `verify`.
- `tldr` may warn that it has no candidate on Ubuntu; `tealdeer` replaces it.

## Tests

- Container tests on `ubuntu:26.04` and `archlinux:latest`: the full bootstrap twice, for the personal and work profiles, with every checkpoint and the variant switch.
- Container scenario `desktop`: Ghostty, the font and its config are installed natively, and skipped on WSL.
- Container scenario `selector`: the menu-free path gives the same chezmoi data as the flags, and a gum with a wrong sha256 is refused.
