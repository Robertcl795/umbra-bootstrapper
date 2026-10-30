# themes

Generated copies of Umbra's theme files, written by `themes/generate.py` in the Umbra umbrella from `brand/tokens/umbra.json` (ADR 0013, 0014). chezmoi deploys them with `include "../themes/…"`. Never edit by hand: change the tokens and re-run the generator.

| File | Deployed to |
|---|---|
| `shell/colors.zsh` | `~/.config/zsh/colors.zsh` |
| `shell/colors.fish` | `~/.config/fish/conf.d/umbra-colors.fish` (fish only) |
| `bat/Umbra.tmTheme` | `~/.config/bat/themes/Umbra.tmTheme` |
| `omarchy/umbra/colors.toml`, `icons.theme` | `~/.config/omarchy/themes/umbra/` (Omarchy only) |
