# Phase 5 — Neovim

Script: [`install/nvim.sh`](../../install/nvim.sh)

Installs `neovim` via the OS package manager if missing, then symlinks the
repo's [`nvim/`](../../nvim) directory to `~/.config/nvim` (backing up any
existing config).

Config entry point is [`nvim/init.lua`](../../nvim/init.lua), plugins live
under `nvim/lua/plugins/` and are managed by
[lazy.nvim](https://github.com/folke/lazy.nvim).

## OS notes

Same package (`neovim`) on both apt and pacman; no version pinning or
release-binary fallback here.

## Test

[`tests/05_nvim.sh`](../../tests/05_nvim.sh) runs
`nvim --headless "+Lazy! sync" +qa` and checks it exits 0 — this is also
the fastest way to manually re-sync plugins after editing
`nvim/lua/plugins/`.
