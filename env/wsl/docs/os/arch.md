# OS notes — WSL Arch

Entry point: `bootstrap.sh` (auto-detects Arch via `/etc/os-release`,
`ID=arch`; see [00-preflight.md](../sections/00-preflight.md)).

## First boot (root, no user yet)

A brand-new Arch WSL starts as **root**, with no regular user, no `sudo` and no
`git`. `bootstrap.sh` detects this case (`id -u` = 0 **and** `ID=arch` **and**
running under WSL) and runs stage 1, `install/stage1.sh`:

1. Moves off `/mnt/*`.
2. Sets up the pacman keyring if the image's first-launch script has not run,
   then `pacman -Syu` with `base-devel`, `git` and `sudo`.
3. Creates your user, from `--user`, `UM_USERNAME` or a prompt, in `wheel`.
   The password comes from a terminal or `UM_USER_PASSWORD_FILE`; otherwise the
   account stays locked and the run says how to set one.
4. Adds `/etc/sudoers.d/10-wheel` and a temporary `zz-umbra-bootstrap` rule for
   passwordless sudo, both checked with `visudo`.
5. Merges `[boot] systemd=true` and `[user] default=<name>` into `/etc/wsl.conf`.
6. Stages the repo at `~/dev/umbra-bootstrapper`, writes the marker
   `~/.local/state/um/bootstrap.env` and installs a temporary `umbra` command.

Then it stops and prints what to run. A distro only picks up its default user
after a restart:

```powershell
wsl.exe --terminate archlinux
wsl.exe -d archlinux
```

```bash
umbra bootstrap resume   # stage 2; safe to run again if it fails
umbra bootstrap status   # what is pending, and whether sudo is still passwordless
```

When stage 2 succeeds, the marker, the `umbra` command and the temporary sudo
rule are removed, and sudo asks for a password again. Until then, passwordless
sudo stays on.

```bash
bash install.sh --yes --user yourname   # no terminal needed for stage 1
```

## Troubleshooting first boot

| You see | Cause | Fix |
|---|---|---|
| `error: keyring is not writable` | older versions, on a distro made with `wsl --import` | update the bootstrapper; stage 1 sets up the keyring |
| `No username: pass --user <name>` | no terminal and no `UM_USERNAME` | add `--user <name>` |
| `This distro already has users: …` | root run on a distro that is already set up | add `--user <name>` |
| `need root for: …` | no usable sudo after stage 2 | set a password: `wsl.exe -d <distro> -u root passwd <name>` |
| `Nothing to resume` | stage 2 already finished | nothing to do |

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
