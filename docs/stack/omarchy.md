# Omarchy

On [Omarchy](https://learn.omacom.io), Omarchy owns its defaults. Umbra adds a theme, a shell and a few tools, and changes nothing else.

## What Umbra installs

| Piece | How |
|---|---|
| The Umbra theme | `omarchy theme install https://github.com/Robertcl795/omarchy-umbra-theme.git`; a bundled copy plus `omarchy theme set umbra` when the repo is unreachable |
| zsh and Starship | chezmoi deploys only `~/.zshrc`, `~/.config/zsh/` and `~/.config/starship.toml` |
| Missing CLI tools | `pacman -S --needed` for what Omarchy lacks; never `pacman -Syu` |

Never touched: Omarchy's editor, terminal, fonts, updates, `~/.bashrc` and login shell. Omarchy themes Neovim, btop, Waybar, Hyprland and the terminals itself, so chezmoi deploys none of their Umbra files here.

## How themes apply

The theme repo holds `colors.toml`, `icons.theme`, two 4K wallpapers and `preview.png`. Omarchy renders the config of every app it themes (Ghostty, Alacritty, Kitty, btop, Hyprland, Hyprlock, Mako, SwayOSD, Walker, Waybar) from `colors.toml`. It uses the keys shared by 17 of the 22 bundled themes (checked on Omarchy 4.0.6), without the optional `orange` and `brown`, plus the Hyprland border keys. Switch back to it later with `omarchy theme set umbra`.

The prompt and the zsh colors follow the bootstrapper's `theme` value. The Omarchy theme itself is umbra only.

## Known limits

- Void and lux Omarchy themes are Planned.
- `preview.png` is a placeholder until a real screenshot exists.
- Containers only simulate Omarchy (`UM_OS=omarchy` with a stub `omarchy` command). A real Omarchy machine is a manual check.

## Tests

- Container scenario `omarchy` (Arch): the theme is installed or the bundled copy is used; only the zsh files and `starship.toml` are deployed; tools come from `pacman -S --needed`; no `pacman -Sy`.
- Container scenario `theme-repo` (Arch): the theme repo's layout, its own `scripts/verify.sh`, and deployment into `~/.config/omarchy/themes/umbra/`.
- Manual checks `omarchy-theme` and `omarchy-wallpapers` on a real Omarchy.
