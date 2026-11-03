# WSL (Arch and Ubuntu)

WSL Arch and WSL Ubuntu 26.04. You get every component from the [stack overview](README.md), plus WSL tuning. The desktop component is not offered: GUI apps run on the Windows side.

## What Umbra installs

The same phases as native Linux (see [linux.md](linux.md) for package sources), plus:

- **Fresh distro (stage 1, as root):**
  - moves off `/mnt/*`;
  - sets up the pacman keyring if needed, then updates the system and installs `base-devel`, `git` and `sudo` (Arch; Ubuntu upgrades nothing);
  - creates your user in `wheel` or `sudo`, with a temporary passwordless sudo rule (checked with `visudo`);
  - merges `[boot] systemd=true` and `[user] default=<name>` into `/etc/wsl.conf`;
  - stages the repo at `~/dev/umbra-bootstrapper` and installs a temporary `umbra` command.

  It then stops for the restart: see [Getting started](../../README.md#fresh-wsl-the-restart-point). When stage 2 succeeds, the marker, the `umbra` command and the sudo rule are removed.
- **`wsl` phase:**
  - merges systemd, interop and automount `metadata` into `/etc/wsl.conf`, with a backup only when it changes;
  - warns when the checkout or the shell is under `/mnt/*` and moves the shell home (`UM_NO_AUTOCD=1` keeps it there);
  - adds `explorer` and `winhome` aliases.
- **Detection:** WSL version, kernel, interop, systemd, networking mode, `wslc`, the filesystem of Windows drives, and whether `/etc/wsl.conf` keys are active. Logged at start and reported by the doctor. The code reads capabilities and never branches on the version number.

The Windows `.wslconfig` affects every distro, so it is written only with `--enable-wslconfig` (`UM_ENABLE_WSLCONFIG=1`). Otherwise the recommended settings are printed. The work profile never writes it.

| Variable (flag) | Values | Default |
|---|---|---|
| `UM_USERNAME` (`--user`) | the user stage 1 creates or reuses | asked on a terminal |
| `UM_USER_PASSWORD_FILE` | a file holding that user's password | asked on a terminal; otherwise the account stays locked |
| `UM_ENABLE_WSLCONFIG` (`--enable-wslconfig`) | `0`, `1` | `0` |
| `UM_WSL_NETWORKING` | `nat`, `mirrored` | `nat` |
| `UM_IS_WSL` | `0`, `1`; skips detection (tests) | detect |

`/etc/wsl.conf` changes apply after `wsl.exe --terminate <distro>`. `.wslconfig` changes apply once every distro has stopped. The bootstrapper never runs `wsl.exe --shutdown`.

## Tested WSL facts

Measured on WSL 3.0.3.0 (kernel 6.18.54.1, Windows 10.0.26200) on 2026-10-31:
- `/mnt/c` is `9p` (drvfs). Virtiofs is on for WSL containers only.
- The kernel name still ends in `-WSL2`, and `wsl.exe --list --verbose` still reports version 2.
- `wsl.exe --version` prints UTF-16LE. `dnsTunneling` and `autoProxy` default to `true`; `[boot] systemd` defaults to `false`.

Sources: [WSL releases](https://github.com/microsoft/WSL/releases) and [wsl-config](https://learn.microsoft.com/windows/wsl/wsl-config).

Still `verify`:
- whether "WSL 3" is more than a release number;
- when distro `/mnt/*` moves to virtiofs;
- whether translated `wsl.exe` output parses on a real non-English Windows.

## How themes apply

As in the [overview](README.md#themes). In Windows Terminal, add the scheme `themes/terminals/windows-terminal/umbra.json` (or `-void`, `-lux`) from this repo to `schemes` in `settings.json`, then pick it for the WSL profile. Choose a Nerd Font there too.

## Known limits

- Keep projects under `~/`: cross-OS I/O under `/mnt/c` is 10–20× slower.
- After a full Arch bootstrap, `metadata` on `/mnt/*` needs one more restart.
- A real terminal is still a manual check: typed passwords, the gum menu, and the restart by hand.

## Tests

- Gates on real, disposable WSL distros (`umbra-test-*`, created and removed by the umbrella's test scripts): fresh Arch and Ubuntu 26.04 as root, the piped command, the restart, stage 2. They never touch the session's own distro and never shut WSL down.
- Container runs with `UM_IS_WSL=1` for the `wsl` phase.
- Checkpoint `08_wsl.sh` and the doctor report.
