# Phase 8 — Language toolchains (rustup / fnm / uv)

Script: [`install/dev/lang.sh`](../../install/dev/lang.sh)

Installs three version-manager-style toolchains (this repo dropped `mise`
in favor of dedicated per-language managers):

- **[rustup](https://rustup.rs)** — Rust. Arch: `pacman -S rustup`.
  Everywhere else: the official `sh.rustup.rs` installer
  (`--no-modify-path`, since shell RC files handle `PATH` themselves).
  Defaults to the `stable` toolchain if none is active yet.
- **[fnm](https://github.com/Schniz/fnm)** (Fast Node Manager) — installed
  into `~/.local/bin` via the official installer; installs Node LTS
  automatically if no version is present yet.
- **[uv](https://astral.sh/uv)** — Python packaging/env manager. Arch:
  `pacman -S uv`. Everywhere else: the official `astral.sh/uv` installer.

Each install exports `PATH` for the *current* process so later phases
(notably phase 9's AI tooling and phase 11's context DB) can use these
tools immediately, without waiting for a new shell session.

## OS notes

Arch has first-party `rustup` and `uv` packages; Ubuntu (and everything
else) always uses the upstream installer scripts for both. `fnm` is always
installed via its own script regardless of OS.

## Test

Covered together with phase 9 by
[`tests/07_devstack.sh`](../../tests/07_devstack.sh), which requires
`rustup`, `cargo`, `fnm`, `uv` all be reachable non-interactively (sourcing
`~/.cargo/env` and prepending `~/.local/bin` itself, so it doesn't depend
on a shell restart having happened).
