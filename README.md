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

## Fresh WSL

A distro with no regular user starts as `root`: Arch always, Ubuntu when its first launch was skipped or it was imported. Run the same command as `root`, with `--user <name>` when there is no terminal to ask on. Stage 1 prepares the distro, then stops and prints what to run, because a default user only applies after a restart:

```powershell
wsl.exe --terminate <distro>
wsl.exe -d <distro>
```

```sh
umbra bootstrap resume   # safe to run again if it fails
umbra bootstrap status   # what is pending, and whether sudo is still passwordless
```

Sudo needs no password until stage 2 succeeds, then asks for one again. An Ubuntu that already has its user needs none of this: run the command as that user.

## Troubleshooting

Each of these came from a real run on a fresh distro.

| You see | Cause | What to do |
|---|---|---|
| `need root for: …`, then `no usable sudo for user …`, exit 77 | no terminal to type a password on, and no passwordless sudo | run it in a terminal; the run says which command needed root |
| `No terminal and no UM_USER_PASSWORD_FILE: <user> stays locked` | stage 1 had nowhere to ask for a password | set one with the printed `wsl.exe … passwd <user>` command, or pass `UM_USER_PASSWORD_FILE=<path>` |
| `No username: pass --user <name>` | no terminal to ask on | add `--user <name>` |
| `This distro already has users: …` | stage 1 never guesses a user | add `--user <name>` with one of them |
| `Nothing to resume` | no stage 2 is pending for this user | check `umbra bootstrap status`, and that you are not `root` |
| Still `root` after stage 1 | the distro has not restarted | run the two `wsl.exe` lines above |
| `P1: apply failed` | the package manager or the network | read the output above it, then run the command again |
| `P6: the doctor failed` | a check named above it failed; the marker and the temporary sudo rule stay | fix it, then `umbra bootstrap resume` |
| `[warn] wsl.conf … is not active yet` | `/etc/wsl.conf` changed after the last restart | `wsl.exe --terminate <distro>`, from Windows |
| A warning that `tldr` has no candidate | Ubuntu dropped the package; `tealdeer` replaces it | nothing |

## Layout

| Path | What it holds |
|---|---|
| `install.sh` | the single command: platform detection, selector, hand-over to `env/wsl/bootstrap.sh` |
| `.chezmoiroot` | points chezmoi at `env/`; the repo root is the chezmoi source |
| `env/` (removed) | dotfiles, install phases (`.chezmoiscripts/`), the installer in `env/wsl/` |
| [`themes/`](themes/README.md) | generated theme files that chezmoi includes; never edited by hand |
| `scripts/verify.sh` | static checks, no containers |

Container tests (Ubuntu 26.04, Arch) and the gates on real disposable WSL distros run from the Umbra umbrella, which has this repo at `bootstrapper/`.

## License

MIT for everything in this repository; see [LICENSE](LICENSE).
