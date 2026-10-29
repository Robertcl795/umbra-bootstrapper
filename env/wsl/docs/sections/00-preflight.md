# Phase 0 — Preflight & OS detection

Script: [`install/detect_os.sh`](../../install/detect_os.sh)

Runs before anything else. It:

1. Warns (but doesn't stop) if you're not under WSL — this bootstrap targets
   WSL Arch/Ubuntu; running it on bare-metal Linux mostly works but isn't
   the tested path.
2. Reads `/etc/os-release` and sets `UM_OS` to `ubuntu` or `arch`. Any
   other `ID` is a hard failure — there is no generic/"other Linux" path.
3. Checks `curl`/`wget` exist and that `https://example.com` is reachable.
   No network, no bootstrap — this fails fast rather than letting later
   phases fail confusingly one package at a time.
4. Checks `sudo` is available (every later phase needs it for package
   installs).

## OS notes

- **Ubuntu**: detected via `ID=ubuntu` in `/etc/os-release`.
- **Arch**: detected via `ID=arch`. A *fresh* `archlinux` WSL instance boots
  as root with no regular user — `bootstrap.sh` detects that case itself
  (before `detect_os.sh` even runs) and does first-boot provisioning
  instead; see [os/arch.md](../os/arch.md).

## Troubleshooting

- `Cannot detect OS: /etc/os-release not found` — you're not on a
  standard Ubuntu/Arch image.
- `Network check failed` — check the WSL network settings in
  [10-wsl.md](10-wsl.md), or your host's proxy/firewall.
