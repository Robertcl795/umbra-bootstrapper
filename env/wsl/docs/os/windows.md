# OS notes — Native Windows (PowerShell, no WSL)

> **Deferred.** The native Windows installer is not part of Umbra v0.2; it stays in the
> [lux-dotfiles repository](https://github.com/Robertcl795/dotfiles/blob/1b1239a) and this page describes it there.
> Its commands below still point at that repository. Windows Terminal color schemes
> live in `themes/terminals/windows-terminal/` as Phase 1 references.

Entry point: [`bootstrap.ps1`](https://github.com/Robertcl795/dotfiles/blob/1b1239a/bootstrap.ps1). This is a completely
separate path from `bootstrap.sh` — it never touches WSL, and running it
does not require a WSL distro to be installed at all. If you want WSL
Arch/Ubuntu instead (or in addition), see
[ubuntu.md](ubuntu.md)/[arch.md](arch.md) and use `bootstrap.sh` there.

## Prerequisite: run this from pwsh, not Windows PowerShell 5.1

`bootstrap.ps1` itself only requires PowerShell 5.1 (`#Requires -Version
5.1`) to kick off — cloning the repo and running `windows/packages.ps1`
work fine there. But **`packages.ps1` never installs `pwsh` itself** (no
`pwsh` entry in its scoop app list), and `windows/profile.ps1` writes its
managed block to `$PROFILE.CurrentUserAllHosts`, which resolves relative to
whichever host is *currently running the script*. Launch the one-liner from
Windows PowerShell 5.1 (Windows' shipped default) and the prompt/alias
block lands in 5.1's own profile path — a file pwsh never reads — so the
new prompt, theme and aliases silently never show up.

Install pwsh yourself first, then run the bootstrap from inside it:

```powershell
winget install Microsoft.PowerShell   # or: scoop install pwsh
pwsh                                   # switch into pwsh
irm https://raw.githubusercontent.com/Robertcl795/dotfiles/main/bootstrap.ps1 | iex
```

## One-line install

```powershell
irm https://raw.githubusercontent.com/Robertcl795/dotfiles/main/bootstrap.ps1 | iex
```

Or cloned:

```powershell
git clone https://github.com/Robertcl795/dotfiles.git $HOME\.dotfiles
& "$HOME\.dotfiles\bootstrap.ps1"
```

Non-interactive, with explicit theme/K8s choice:

```powershell
& .\bootstrap.ps1 -NonInteractive -Theme cyber -EnableK8s 1
```

## Phases (`windows/`, orchestrated by `windows/run.ps1`)

| Script | Does |
| --- | --- |
| `windows/common.ps1` | Logging, backups, `Confirm-Action`, theme selection — the Windows equivalent of `install/common.sh`. Dot-sourced by every other script in this list. |
| `windows/packages.ps1` | Installs [scoop](https://scoop.sh) itself if missing, adds the `extras`/`versions` buckets, then installs the CLI stack. |
| `windows/profile.ps1` | Writes a managed block into the pwsh `$PROFILE` (idempotent — re-running replaces only the block between `# >>> dotfiles managed block` markers, your own additions above/below are untouched): prompt, PSReadLine predictions, PSFzf bindings, modern-CLI aliases, [git aliases](../CHEATSHEET.md#git), and the fastfetch greeting. Also junctions `config\fastfetch` into `~\.config\fastfetch`. |
| `windows/terminal.ps1` | Adds all four `themes/*/windows-terminal.json` color schemes to Windows Terminal's `settings.json` and applies the selected one **to the PowerShell profile entry only**. |
| `windows/summary.ps1` | Same installed-tools summary as the bash side, printed at the end of a successful run — see [13-summary.md](../sections/13-summary.md). |

## Package manager: scoop, not apt/pacman

`Install-ScoopApp` in `windows/packages.ps1` tries a scoop manifest for
each tool and warns (never aborts) if one doesn't exist — mirroring the
`|| log_warn` pattern used throughout the bash scripts. `sshs` has no
scoop manifest at all, so it's pulled from its GitHub release zip instead
(`Install-ReleaseBinary`, into `%USERPROFILE%\.local\bin`), the same
pattern `install/packages/ubuntu.sh` uses for tools apt doesn't have.

Covered (majority of the WSL stack, same names): `git`, `7zip`,
`starship`, `ripgrep`, `fd`, `bat`, `eza`, `fzf`, `zoxide`, `neovim`,
`lazygit`, `glow`, `duf`, `lnav`, `just`, `zellij`, `yazi`, `lazydocker`,
`fastfetch`, `sshs`, `rustup`, `fnm`, `uv`, `gh`, plus `claude`/`opencode` via their
official `.ps1` installers, and `kubectl`/`helm`/`k3d` if
`UM_ENABLE_K8S=1`.

**Not covered** (WSL/bash-only, no native-Windows equivalent yet): fish
shell setup, the `config/zsh` modules, `install/link.sh`'s symlink-based
dotfile linking, and phase 11's AI Development Standard deployment
(`ai/` → `~/.claude/*`, context DB). `k3d` additionally
requires Docker Desktop with the WSL2 backend, since it runs containers
either way. **`pwsh` (PowerShell 7) itself is also not installed** — see
the prerequisite callout above; every other tool in this list installs
fine from Windows PowerShell 5.1, but the profile/theme/alias block only
works once you're actually running pwsh.

## Prompt theme — same files, different mechanism

Real symlinks on Windows need admin rights or Developer Mode, so instead
of symlinking (like phase 2/4 on the bash side), `windows/profile.ps1`
points `$env:STARSHIP_CONFIG` directly at
`<dotfiles>\themes\<theme>\starship.toml` inside the cloned repo. It's the
exact same theme file used by WSL — pulling repo updates (`git pull`)
updates both the WSL and native-Windows prompt.

## Terminal theme (native-Windows-only — no WSL equivalent)

Windows Terminal's color scheme is a Windows-side setting with no
counterpart in the bash bootstrap at all (WSL profiles in Windows Terminal
are just another entry in the same `settings.json`, and `windows/
terminal.ps1` deliberately leaves them alone — see below). `windows/
terminal.ps1`:

1. Locates `settings.json` (checks the Store-package path, the Preview
   Store-package path, and the unpackaged path, in that order).
2. Backs it up (`settings.json.backup.<timestamp>`) before touching it.
3. Strips full-line `//` comments (settings.json is JSONC, not strict
   JSON — this is a best-effort transform, not a full JSONC parser; if
   parsing still fails, the file is left completely untouched and a
   warning is printed rather than risking corruption).
4. Merges in all four `themes/*/windows-terminal.json` schemes
   (`dotfiles-tron`, `dotfiles-cyber`, `dotfiles-eva01`, `dotfiles-minimal`)
   by name — existing schemes with other names are kept as-is.
5. Sets `colorScheme` **only** on profile entries that look like
   PowerShell (`commandline` matching `pwsh`/`powershell.exe`, `name`
   starting with `PowerShell`, or `source` matching
   `Windows.Terminal.PowershellCore`) — your WSL/Ubuntu/cmd profiles keep
   whatever scheme they already had.

## Network settings are genuinely different here — read this

This is the one place the two bootstrap paths actively diverge in
behavior, not just mechanism: **`install/wsl.sh` (phase 10) and its
`.wslconfig`/`wsl.conf` mirrored-networking setup do not apply to this
path at all**, and `bootstrap.ps1`/`windows/run.ps1` don't attempt any
equivalent. A native Windows process talks to the network directly through
the normal Windows stack — there's no WSL NAT/mirrored-networking layer,
no `dnsTunneling`, no `autoProxy` setting to configure, and no
`wsl --shutdown` needed after changes here. If `Install-Scoop`,
`Invoke-WebRequest`, or `git clone` needs a proxy, that's ordinary Windows
proxy configuration (`netsh winhttp show proxy`, or your org's system-wide
proxy settings) — nothing this bootstrap manages. See
[10-wsl.md](../sections/10-wsl.md) for what the WSL side actually
configures, for contrast.

## Test

No `tests/*.ps1` checkpoints yet (the `tests/` directory is bash-only,
written for the WSL path). `windows/summary.ps1`'s output after a run is
the closest equivalent — verify it manually.
