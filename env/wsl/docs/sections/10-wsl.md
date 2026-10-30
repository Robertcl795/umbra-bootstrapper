# Phase 10 — WSL interop & networking optimizations

Script: [`install/wsl.sh`](../../install/wsl.sh)

**Native-Windows callout:** everything in this phase is WSL-specific and is
completely skipped by `bootstrap.ps1`. The native PowerShell path has no
`.wslconfig`/`wsl.conf` equivalent — your network settings there are just
whatever Windows itself is already using. See
[os/windows.md](../os/windows.md) for what *does* differ on that path
(scoop's own proxy handling, if any).

No-ops entirely if not running under WSL. `.wslconfig` is written only with `--enable-wslconfig`.

## What it changes

- **`/etc/wsl.conf`** (inside the Linux distro, needs `sudo`): enables
  systemd, `generateHosts`/`generateResolvConf`, Windows PATH interop, and
  NTFS-mount permission metadata. Backs up the existing file first and
  preserves whatever `[user] default=` was already set (so a re-run never
  silently drops you back to root).
- **`%USERPROFILE%\.wslconfig`** (on the Windows host, found via `wslvar`
  or a `cmd.exe` interop call): sets `[wsl2] networkingMode=mirrored`,
  `dnsTunneling=true`, `autoProxy=true`. Backed up first. Requires
  Windows 11 22H2+; WSL silently falls back to NAT networking on older
  builds.
- Warns if the umbra checkout (or your current directory) lives under
  `/mnt/*` — cross-OS I/O there is 10-20x slower than the native ext4
  filesystem.

`/etc/wsl.conf` is merged: other keys are kept, and a backup is written only
when something changes. It applies after `wsl.exe --terminate <distro>`.
`.wslconfig` applies once every distro has stopped.

## Customization

`UM_ENABLE_WSLCONFIG=0|1` (default `0`)

## Test

[`tests/08_wsl.sh`](../../tests/08_wsl.sh) — exits 0 immediately outside
WSL; otherwise checks `systemd=true` in `/etc/wsl.conf` and warns
(non-fatally) about missing `.wslconfig` keys or an NTFS-hosted repo.
