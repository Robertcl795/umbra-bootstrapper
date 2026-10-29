# OS notes — WSL Arch

Entry point: `bootstrap.sh` (auto-detects Arch via `/etc/os-release`,
`ID=arch`; see [00-preflight.md](../sections/00-preflight.md)).

## First boot (root, no user yet)

A brand-new `wsl -d archlinux` instance starts as **root** with no regular
user. `bootstrap.sh` detects this specific case (`id -u` = 0 **and**
`ID=arch` **and** running under WSL, checked *before* `detect_os.sh` even
runs) and does one-time provisioning instead of the normal bootstrap:

1. Moves off `/mnt/*` if invoked from there (9P cross-OS I/O is
   10-20x slower).
2. `pacman -Syu --noconfirm`, installs `sudo`, grants the `wheel` group
   sudo access.
3. Prompts for a username (or reads `UM_USERNAME` non-interactively),
   creates that user with `useradd -m -G wheel`, sets its password.
4. Writes `/etc/wsl.conf` with `systemd=true` and `[user] default=<name>`
   (backing up any existing `wsl.conf` first), then exits and tells you to
   run `wsl --shutdown` from PowerShell and reopen.

Reopening Arch after that logs you in as the new user — run the same
bootstrap command again and it proceeds as a normal (non-root) run.

```powershell
wsl --shutdown
wsl -d archlinux
```

```bash
UM_USERNAME=yourname bash bootstrap.sh   # non-interactive first boot
```

## What's different from Ubuntu here

Arch's official repos are much more current, so almost nothing needs a
release-binary fallback: `tldr`, `zellij`, `lazygit`, `glow`,
`lazydocker`, `yazi`, `lnav`, `just`, and `starship` itself all come
straight from `pacman`. See [01-packages.md](../sections/01-packages.md).

The one exception is **`sshs`**, which isn't in the official repos:
`install/packages/arch.sh` tries, in order, AUR (via `yay`, bootstrapped
from the `yay-bin` PKGBUILD if `yay` itself is missing), then
`cargo install sshs`, then a GitHub release binary — warning (not failing)
if all three don't work out.

Also initializes the pacman keyring (`pacman-key --init --populate
archlinux`) if it looks uninitialized, which a fresh Arch image needs
before any package install will succeed.

## Known-good install

```bash
git clone https://github.com/Robertcl795/umbra.git ~/dev/umbra
bash ~/dev/umbra/env/wsl/bootstrap.sh
# once the repo is public (Phase 5):
# curl -fsSL https://raw.githubusercontent.com/Robertcl795/umbra/main/env/wsl/bootstrap.sh | bash
```
