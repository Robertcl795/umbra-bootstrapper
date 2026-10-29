# Phase 7 — Zellij multiplexer

Script: [`install/zellij.sh`](../../install/zellij.sh)

Zellij replaces tmux as the terminal multiplexer in this repo (the
`--enable-tmux`/`--disable-tmux` bootstrap flags are deprecated no-ops kept
only so old commands don't hard-fail). Installs via pacman on Arch, a
GitHub release binary on Ubuntu (same `install_release_bin` mechanism as
phase 1), or `cargo install zellij` as a last resort — then symlinks
[`config/zellij/config.kdl`](../../config/zellij/config.kdl) to
`~/.config/zellij/config.kdl`.

## OS notes

Arch ships zellij directly in the official repos; Ubuntu does not, so it
comes from the upstream release tarball instead (`~/.local/bin/zellij`).

## Test

No dedicated `tests/07_*.sh` — the config symlink is covered by
[`tests/02_linking.sh`](../../tests/02_linking.sh)
(`check_link ~/.config/zellij/config.kdl`).
