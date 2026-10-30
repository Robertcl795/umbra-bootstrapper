# Umbra Bootstrapper

Sets up a themed developer environment on WSL (Ubuntu, Arch) with one command: packages, zsh, Starship, Neovim, zellij, Kubernetes and language tools, and the dotfiles, deployed by [chezmoi](https://www.chezmoi.io/). Part of Umbra; the umbrella repo is private for now.

```sh
curl -fsSL https://raw.githubusercontent.com/Robertcl795/umbra-bootstrapper/main/env/wsl/bootstrap.sh | bash
```

Non-interactive: `bash env/wsl/bootstrap.sh --yes --profile personal|work [--components a,b] [--skip c]`. Details in [env/wsl/README.md](env/wsl/README.md).

## Layout

| Path | What it holds |
|---|---|
| `.chezmoiroot` | points chezmoi at `env/`; the repo root is the chezmoi source |
| [`env/`](env/README.md) | dotfiles, install phases (`.chezmoiscripts/`), the installer in `env/wsl/` |
| [`themes/`](themes/README.md) | generated theme files that chezmoi includes; never edited by hand |
| `scripts/verify.sh` | static checks, no containers |

Container tests (Ubuntu 26.04, Arch) run from the Umbra umbrella, which mounts this repo at `bootstrapper/`.

## License

MIT for everything in this repository; see [LICENSE](LICENSE).
