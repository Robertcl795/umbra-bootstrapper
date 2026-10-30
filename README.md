# Umbra Bootstrapper

One command sets up a themed developer environment: packages, zsh, Starship, Neovim, zellij, Kubernetes and language tools, and the dotfiles, deployed by [chezmoi](https://www.chezmoi.io/). Part of Umbra; the umbrella repo is private for now.

```sh
curl -fsSL https://raw.githubusercontent.com/Robertcl795/umbra-bootstrapper/main/install.sh | bash
```

It detects the system and shows a menu ([gum](https://github.com/charmbracelet/gum), downloaded pinned and sha256-checked):

| System | What it offers |
|---|---|
| WSL Ubuntu, WSL Arch | every component, plus WSL tuning |
| Ubuntu, Arch (native) | every component, plus Ghostty and JetBrainsMono Nerd Font themed with the Umbra colors (pre-selected when a desktop session is running) |
| Omarchy | the Umbra theme (`omarchy theme install`), then only zsh, Starship and the tools Omarchy lacks (`pacman -S --needed`); Omarchy keeps its editor, terminal, fonts, updates and login shell |

Umbra AI (the `um` CLI, vault, AI standard, AI CLIs, Ollama) is private: the menu offers it only when your GitHub credentials (`gh auth login` or an SSH key) can read it.

Without a menu: `bash install.sh --yes [--profile personal|work] [--components a,b] [--skip c]`, or `UM_SELECT=packages,shell bash install.sh`. `--dry-run` prints what would run. The WSL installer alone: `bash env/wsl/bootstrap.sh --yes`. Details in [env/wsl/README.md](env/wsl/README.md).

## Layout

| Path | What it holds |
|---|---|
| `install.sh` | the single command: platform detection, selector, hand-over to `env/wsl/bootstrap.sh` |
| `.chezmoiroot` | points chezmoi at `env/`; the repo root is the chezmoi source |
| [`env/`](env/README.md) | dotfiles, install phases (`.chezmoiscripts/`), the installer in `env/wsl/` |
| [`themes/`](themes/README.md) | generated theme files that chezmoi includes; never edited by hand |
| `scripts/verify.sh` | static checks, no containers |

Container tests (Ubuntu 26.04, Arch) run from the Umbra umbrella, which mounts this repo at `bootstrapper/`.

## License

MIT for everything in this repository; see [LICENSE](LICENSE).
