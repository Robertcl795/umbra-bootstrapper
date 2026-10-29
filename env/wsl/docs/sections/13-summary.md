# Post-bootstrap — Installed tools summary

Script: [`install/summary.sh`](../../install/summary.sh)

Runs automatically as the last chezmoi script (or the last step of `install/run.sh`), after phase 12
succeeds — and *only* then: `install/run.sh` has `set -euo pipefail`, so if
any earlier phase's script exits non-zero the whole run stops before this
point is ever reached. There's no separate "did it work" flag to check;
reaching the summary at all means every phase returned 0.

For each tool it checks `PATH` for the primary command (or a known
alternate, e.g. `eza`/`exa`, `tldr`/`tealdeer`) and prints `installed` or
`not found`, plus a version string for tools with a fast, known-safe
version flag. Version calls are wrapped in `timeout 3` and only attempted
for commands known not to launch an interactive TUI if run bare (`sshs`,
`yazi`, `lazydocker`, etc. are checked for presence only, never executed) —
so the summary itself can never hang the end of a successful bootstrap.

Since each `install/*.sh` phase runs as its own `bash foo.sh --run`
process, `PATH` changes made inside one phase (rustup, fnm, uv, Claude
Code, opencode all install into `~/.cargo/bin` / `~/.local/bin` /
`~/.opencode/bin`) don't automatically carry over to the next process —
`install/summary.sh` re-adds those directories to its own `PATH` before
checking anything, so first-run tools show up correctly without needing a
new shell session.

Re-run it standalone any time:

```bash
UM_SHELL=zsh UM_THEME=cyber UM_ENABLE_K8S=1 bash install/summary.sh --run
```

## OS notes

Native Windows has the equivalent
[`windows/summary.ps1`](https://github.com/Robertcl795/dotfiles/blob/1b1239a/windows/summary.ps1) (`Show-Summary`),
covering the same tool list translated to scoop/pwsh naming — see
[os/windows.md](../os/windows.md).
