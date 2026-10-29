# Phase 1 — System update + base packages

Scripts: [`install/packages/ubuntu.sh`](../../install/packages/ubuntu.sh),
[`install/packages/arch.sh`](../../install/packages/arch.sh)

Installs the base toolchain and modern CLI stack: `git curl wget unzip
ca-certificates ripgrep fd bat eza fzf zoxide neovim starship tldr zsh`
plus `lazygit glow duf lazydocker yazi sshs lnav just zellij fastfetch`.
`fish` is added only when it is the chosen shell (ADR 0004).

Full matrix of what each tool replaces and how to reach it:
[TOOLS.md](../TOOLS.md).

## Ubuntu

- Uses `apt-get`. Ubuntu's archive lags upstream, so several tools
  (`lazygit`, `glow`, `lazydocker`, `zellij`, `yazi`, `sshs`, `fastfetch`
  before 24.10, and `duf` if apt doesn't have it) are installed straight
  from GitHub release binaries
  into `~/.local/bin` instead — see `install_release_bin` in
  [`install/common.sh`](../../install/common.sh). Override pinned versions
  with `UM_LAZYGIT_VERSION`, `UM_GLOW_VERSION`, `UM_LAZYDOCKER_VERSION`,
  `UM_DUF_VERSION`.
- `rg`/`fd`/`bat`/`eza` sometimes ship under different package names
  (`fd-find`/`fdfind`, `bat`/`batcat`, `eza`/`exa`); the script installs
  whichever exists and symlinks the canonical name into `~/.local/bin` if
  needed.
- **`tldr`/`eza` candidate check**: don't gate the install on `apt-cache
  show <pkg>` — it can return success even when apt has no installable
  candidate for the current release/arch (stale/partial index state), which
  used to abort the entire bootstrap under `set -e` the moment `apt-get
  install` then failed. Both packages are installed via a direct
  `apt-get install` attempt with a fallback (`tealdeer` for `tldr`, `exa`
  for `eza`) and a warning if neither is installable — nothing here should
  ever kill the run.

## Arch

- Uses `pacman`, with almost everything available directly from the
  official repos (including `tldr`, `zellij`, `lazygit`, `glow`,
  `lazydocker`, `yazi`, `lnav`, `just`, `fastfetch` — no release-binary
  fallback needed).
- `sshs` isn't in the official repos: tries AUR via `yay` (bootstrapped
  from the `yay-bin` PKGBUILD if missing) first, then `cargo install sshs`,
  then a GitHub release binary.
- Initializes the pacman keyring (`pacman-key --init/--populate`) if it
  looks uninitialized — needed on a fresh install.

## Windows (native PowerShell)

Different package manager entirely (scoop, not apt/pacman) and a smaller
guaranteed-available set — see [os/windows.md](../os/windows.md).

## Customization

`UM_LAZYGIT_VERSION`, `UM_GLOW_VERSION`, `UM_LAZYDOCKER_VERSION`,
`UM_DUF_VERSION` (Ubuntu only) pin release-binary versions.

## Test

[`tests/01_packages.sh`](../../tests/01_packages.sh) asserts every tool
above is on `PATH` (accepting the alternate package names).
