# Phase 10 — WSL interop & networking optimizations

Script: [`install/wsl.sh`](../../install/wsl.sh)

**Native-Windows callout:** everything in this phase is WSL-specific and is
completely skipped by `bootstrap.ps1`. The native PowerShell path has no
`.wslconfig`/`wsl.conf` equivalent — your network settings there are just
whatever Windows itself is already using. See
[os/windows.md](../os/windows.md) for what *does* differ on that path
(scoop's own proxy handling, if any).

No-ops entirely if not running under WSL, or if `UM_ENABLE_WSLCONFIG=0`.

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

Changes to `.wslconfig` need `wsl --shutdown` (from PowerShell) and a
terminal reopen to take effect — the script prints this reminder.

## Customization

`UM_ENABLE_WSLCONFIG=0|1` (default `1`)

## Test

[`tests/08_wsl.sh`](../../tests/08_wsl.sh) — exits 0 immediately outside
WSL; otherwise checks `systemd=true` in `/etc/wsl.conf` and warns
(non-fatally) about missing `.wslconfig` keys or an NTFS-hosted repo.
