# Umbra Bootstrapper

One command sets up a themed developer environment: packages, zsh, Starship, Neovim, zellij, Kubernetes and language tools. [chezmoi](https://www.chezmoi.io/) deploys the dotfiles. One palette covers every app, in three variants: umbra, void and lux.

- [Getting started](#getting-started)
- [Philosophy](docs/philosophy.md)
- [Stack](docs/stack/README.md): [Omarchy](docs/stack/omarchy.md) · [Arch and Ubuntu](docs/stack/linux.md) · [WSL](docs/stack/wsl.md) · [Planned](docs/stack/planned.md)

## Getting started

Every platform uses the same command. It follows the `main` branch.

```sh
curl -fsSL https://raw.githubusercontent.com/Robertcl795/umbra-bootstrapper/main/install.sh | bash
```

To read the script before you run it:

```sh
curl -fsSL -o install.sh https://raw.githubusercontent.com/Robertcl795/umbra-bootstrapper/main/install.sh
less install.sh && bash install.sh
```

What happens:

1. The installer clones this repo to `~/.local/share/umbra/bootstrapper`.
2. It detects the system and opens **umbra-setup**, the installer's TUI: a system scan, then profile, components, variant and a review of the plan. If umbra-setup cannot be downloaded or verified, the installer stops and says so; run it with `--yes` (and `--profile`, `--components`) to install without the TUI. It offers:

   | System | The menu offers |
   |---|---|
   | WSL Arch, WSL Ubuntu | every component, plus WSL tuning |
   | Arch, Ubuntu (native) | every component, plus Ghostty and JetBrainsMono Nerd Font (pre-selected when a desktop session runs) |
   | Omarchy | the Umbra Omarchy theme, zsh, Starship and the tools Omarchy lacks; Omarchy keeps everything else |

3. It installs what you picked, and chezmoi deploys the dotfiles. umbra-setup shows each phase with its log; `ctrl+c` stops after the running phase, never in the middle of one. The log is kept in `~/.local/state/um/setup-<time>.log`.
4. The last phase runs the doctor (`env/wsl/tests/99_smoke.sh`). The run fails if any check fails.

Run `umbra-setup` again at any time to add components or change the variant or the profile; it opens with what you installed. It needs a terminal of at least 80×24.

To skip the menu, pass `--yes`, and optionally `--profile personal|work`, `--components a,b` or `--skip c`. `--dry-run` prints the plan without running it.

### Fresh WSL: the restart point

A distro with no regular user starts as `root`. That is always the case for Arch, and for Ubuntu when its first launch was skipped or it was imported. Run the same command as `root`. Add `--user <name>` if there is no terminal to ask on.

Stage 1 prepares the distro, then stops: a default user only takes effect after a restart. It prints what to run next:

```powershell
wsl.exe --terminate <distro>
wsl.exe -d <distro>
```

```sh
umbra bootstrap resume   # stage 2 in umbra-setup's progress screen; safe to run again if it fails
umbra bootstrap resume --plain   # the same, as plain log lines
umbra bootstrap status   # what is pending, and whether sudo is still passwordless
```

Sudo needs no password until stage 2 succeeds, then asks for one again. An Ubuntu that already has its user skips all of this: run the command as that user, in a terminal.

### Check it

Run the doctor again at any time:

```sh
bash ~/.local/share/umbra/bootstrapper/env/wsl/tests/99_smoke.sh
```

After a fresh-WSL stage 1, the checkout is `~/dev/umbra-bootstrapper` instead. With Umbra AI installed, `um doctor` also checks the `um` CLI and the vault.

### Verify umbra-setup

`install.sh` runs umbra-setup only when its download matches the sha256 pinned in this repo (`env/wsl/install/checksums.sha256`). When `cosign` is installed it also checks the release's signature, and when `gh` is logged in, its build provenance. A failed check stops the install. To check a release by hand:

```sh
v=X.Y.Z
base=https://github.com/Robertcl795/umbra-bootstrapper/releases/download/v$v
curl -fsSLO "$base/checksums.txt" -O "$base/checksums.txt.sigstore.json" -O "$base/umbra-setup_${v}_linux_amd64.tar.gz"
cosign verify-blob \
  --certificate-identity "https://github.com/Robertcl795/umbra-bootstrapper/.github/workflows/release.yml@refs/tags/v$v" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --bundle checksums.txt.sigstore.json checksums.txt
sha256sum --check --ignore-missing checksums.txt
gh attestation verify "umbra-setup_${v}_linux_amd64.tar.gz" -R Robertcl795/umbra-bootstrapper
```

Every release also carries SBOMs of the archives and the source.

### Pick a variant

The menu asks for umbra (dark, default), void (darkest background) or lux (light). In umbra-setup the whole screen redraws in the variant under the cursor. To switch later:

```sh
UM_THEME=lux chezmoi init --apply
```

The prompt, zsh/fish colors, fzf, bat, zellij, Ghostty and Neovim follow the variant. The other apps get all three theme files. See [Stack › Themes](docs/stack/README.md#themes).

## Troubleshooting

Each of these came from a real run on a fresh distro.

| You see | Cause | What to do |
|---|---|---|
| `need root for: …`, then `no usable sudo for user …`, exit 77 | no terminal to type a password on, and no passwordless sudo | run it in a terminal; the message names the command that needed root |
| `No terminal and no UM_USER_PASSWORD_FILE: <user> stays locked` | stage 1 had nowhere to ask for a password | set one with the printed `wsl.exe … passwd <user>` command, or pass `UM_USER_PASSWORD_FILE=<path>` |
| `No username: pass --user <name>` or `This distro already has users: …` | stage 1 never guesses a user | add `--user <name>` |
| `Nothing to resume` | no stage 2 is pending for this user | check `umbra bootstrap status`, and that you are not `root` |
| Still `root` after stage 1 | the distro has not restarted | run the two `wsl.exe` lines above |
| `P1: apply failed` | the package manager or the network | read the output above it, then run the command again |
| `P6: the doctor failed` | a check named above it failed; the marker and the temporary sudo rule stay | fix it, then `umbra bootstrap resume` |
| `[warn] wsl.conf … is not active yet` | `/etc/wsl.conf` changed after the last restart | `wsl.exe --terminate <distro>`, from Windows |

## Layout

| Path | What it holds |
|---|---|
| `install.sh` | the single command: platform detection, umbra-setup, hand-over to `env/wsl/bootstrap.sh` |
| `cmd/`, `internal/` | umbra-setup, the TUI (Go, Bubble Tea); `env/wsl/install/components.tsv` is its component list |
| `.goreleaser.yaml`, `.github/workflows/release.yml` | the umbra-setup release: checksums, cosign signature, SBOMs, provenance |
| `.chezmoiroot` | points chezmoi at `env/`, so the repo root is the chezmoi source |
| `env/` | dotfiles, install phases (`.chezmoiscripts/`), the installer and its tests in `env/wsl/` |
| `themes/` | generated theme files that chezmoi includes; never edited by hand |
| `docs/` | philosophy and stack pages |
| `scripts/verify.sh` | static checks, unit, Go and PTY tests; no containers |
| `test/pty/` | PTY tests of umbra-setup, and the real-install gate it runs inside a test distro |

Umbra AI (the `um` CLI, vault, AI standard, AI CLIs, Ollama) appears in the menu when the installer can reach its public repo; `UM_AI_ACCESS=0` hides it. What `um` does for you, and how to use it: [the `um` docs](https://github.com/Robertcl795/umbra-ai/tree/main/docs).

## License

MIT for everything in this repository; see [LICENSE](LICENSE).
