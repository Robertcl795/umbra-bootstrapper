# Cheatsheet

Everything this environment actually gives you, in one page. Aliases come
from [`env/dot_config/zsh/`](../../dot_config/zsh) (zsh) and
[`env/dot_config/fish/conf.d/`](../../dot_config/fish/conf.d) (fish) — the two are kept in
sync, and the pwsh profile mirrors the same names on native Windows.

- [Git](#git)
- [Files & navigation](#files--navigation)
- [Search](#search)
- [Keybindings](#keybindings)
- [TUIs](#tuis)
- [Languages](#languages)
- [Kubernetes](#kubernetes)
- [Managing the environment](#managing-the-environment)
- [Troubleshooting](#troubleshooting)

## Git

Every alias completes like the command it wraps — `gco <Tab>` offers
branches, `gbD <Tab>` offers local branches.

**Status & staging**

| Alias | Command | |
| --- | --- | --- |
| `gst` | `git status` | |
| `gss` | `git status --short --branch` | one line per file |
| `ga` | `git add` | |
| `gaa` | `git add --all` | |
| `gap` | `git add --patch` | stage hunk by hunk |
| `grs` | `git restore` | discard working-tree changes |
| `grst` | `git restore --staged` | unstage, keep the changes |

**Commit**

| Alias | Command | |
| --- | --- | --- |
| `gc` | `git commit -v` | diff shown in the editor |
| `gcm` | `git commit -v -m` | |
| `gca` | `git commit -v --amend` | |
| `gcan` | `git commit -v --amend --no-edit` | fix the last commit, keep its message |
| `gcf` | `git commit --fixup` | pairs with `grbi --autosquash` |

**Checkout / switch**

| Alias | Command | |
| --- | --- | --- |
| `gco` | `git checkout` | also restores paths, detaches HEAD |
| `gcob` | `git checkout -b` | |
| `gsw` | `git switch` | branch-only, safer than checkout |
| `gswc` | `git switch -c` | |
| `gswd` | `git switch --detach` | |
| `gsw-` | `git switch -` | previous branch (zsh only) |

**Branch**

| Alias | Command | |
| --- | --- | --- |
| `gb` | `git branch` | |
| `gba` | `git branch --all` | |
| `gbv` | `git branch -vv` | with upstream + last commit |
| `gbd` | `git branch -d` | safe delete — refuses if unmerged |
| `gbD` | `git branch -D` | force delete |
| `gbr` | *(function)* | branches by commit date, newest last |
| `gbclean` | *(function)* | delete every branch already merged into the default branch |

**Diff & log**

| Alias | Command |
| --- | --- |
| `gd` / `gds` / `gdw` | `git diff` / `--staged` / `--word-diff` |
| `gl` | last 20 commits, one line each, with graph |
| `glog` | `git log` (pager quits if it fits one screen) |
| `gadog` | `git log --all --decorate --oneline --graph` |

**Remote**

| Alias | Command | |
| --- | --- | --- |
| `gf` | `git fetch --all --prune` | |
| `gpl` | `git pull --rebase --autostash` | |
| `gp` | `git push` | |
| `gpu` | `git push -u origin HEAD` | push a new branch and track it |
| `gpf` | `git push --force-with-lease` | never plain `--force` |

**Stash / rebase / worktree**

| Alias | Command |
| --- | --- |
| `gsta` / `gstp` / `gstl` | `git stash push` / `pop` / `list` |
| `grb` / `grbi` | `git rebase` / `-i` |
| `grbc` / `grba` | `git rebase --continue` / `--abort` |
| `gwt` | `git worktree` |

> [!NOTE]
> On native Windows the profile removes PowerShell's built-in `gc`
> (Get-Content), `gcm` (Get-Command), `gl` (Get-Location) and `gp`
> (Get-ItemProperty) aliases so the git ones win. Use the full cmdlet names
> there.

## Files & navigation

| Command | What it is |
| --- | --- |
| `ls` | `eza --icons --group-directories-first` |
| `ll` | long listing with git status |
| `la` | long listing including dotfiles |
| `tree` | `eza --tree --icons` |
| `cat FILE` | `bat` — syntax highlighting + line numbers |
| `df` | `duf` |
| `z PART` | zoxide — jump to a directory you've visited |
| `zi` | zoxide interactive picker |
| `cd -` / `-` | previous directory |
| `y` (or `lf`) | yazi; quitting leaves you in the last directory you browsed |
| `vim` | nvim |
| `explorer` | open the current directory in Windows Explorer (WSL) |
| `winhome` | cd to your Windows user profile (WSL) |

`AUTOCD` is on: typing a directory name alone cd's into it.

## Search

| Command | What it is |
| --- | --- |
| `grep PATTERN` | ripgrep — recursive, gitignore-aware, coloured |
| `fd NAME` | fd — fast find with sane defaults |
| `fzf` | fuzzy finder over `fd --type f --hidden` |
| `tldr CMD` | example-first help for a command |

## Keybindings

zsh runs in vi mode ([zsh-vi-mode](https://github.com/jeffreytse/zsh-vi-mode));
`Esc` enters normal mode and the cursor shape follows the mode.

| Key | Does |
| --- | --- |
| `Ctrl+R` | fuzzy history search |
| `Ctrl+T` | fuzzy file picker (with a `bat` preview) |
| `Ctrl+F` | file picker excluding hidden files → inserts the path |
| `Alt+C` | fuzzy cd |
| `↑` / `↓` | history search by what you've typed so far |
| `Ctrl+←` / `Ctrl+→` | move by word |
| `Ctrl+\` | toggle autosuggestions |
| `**<Tab>` | fzf completion anywhere (`cd **<Tab>`, `kill -9 **<Tab>`) |
| `Tab` | completion menu (case-insensitive) |

## TUIs

| Command | What it is |
| --- | --- |
| `lg` | lazygit — stage hunks, rebase, cherry-pick, browse history |
| `ld` | lazydocker — containers, logs, stats |
| `zellij` | terminal multiplexer ([keys](sections/07-zellij.md)) |
| `sshs` | fuzzy picker over `~/.ssh/config` hosts |
| `lnav FILE` | log navigator with parsing and filters |
| `glow FILE.md` | render Markdown in the terminal |
| `ff` | fastfetch (also runs automatically on every new tab) |

## Languages

```bash
rustup show                  # active Rust toolchain
cargo build

fnm install --lts            # install Node LTS
fnm use 20                   # switch; also auto-switches on cd
pnpm install                 # standalone pnpm, no corepack

uv venv                      # create a Python env
uv pip install -r req.txt    # fast pip
uv run script.py

claude                       # Claude Code
opencode                     # opencode
gh copilot suggest "..."     # after: gh auth login
```

## Kubernetes

Installed only when `UM_ENABLE_K8S=1`.

```bash
kubectl get pods
helm list
k3d cluster create dev --agents 2
k3d cluster delete dev
```

## Managing the environment

```bash
# from env/wsl/ in the umbra checkout
bash bootstrap.sh --yes                      # re-run the full bootstrap (idempotent)
bash tests/99_smoke.sh                       # every checkpoint
UM_THEME=tron chezmoi init --apply           # switch prompt theme
chezmoi diff && chezmoi apply                # after editing a dotfile in env/
bash install/fastfetch.sh --run              # reinstall/relink the greeting
bash ../../toolkit/ai-standard/scaffold.sh ~/repo     # drop the AI standard into a repo
# replaced files are kept as <file>.backup.<timestamp>

zplugin-update                   # update the zsh plugins
exec zsh                         # reload the shell
bash install/summary.sh --run    # what's installed, with versions
```

Machine-local settings that shouldn't be committed go in `~/.zshrc.local`:

```bash
export UM_NO_FASTFETCH=1        # no greeting on new tabs
export UM_NO_AUTOCD=1           # don't auto-cd out of /mnt/*
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Boxes/tofu instead of icons | Install a [Nerd Font](https://www.nerdfonts.com/) and select it in the terminal, or switch to the `cyber` theme |
| Slow shell startup | `time zsh -i -c exit`, then bisect by commenting modules out of `env/dot_zshrc.tmpl` |
| Completions stale or broken | `rm ~/.cache/zsh/zcompdump && exec zsh` |
| A plugin failed to load | `rm -rf ~/.local/share/zsh/plugins && exec zsh` (they re-clone) |
| Greeting doesn't appear | `command -v fastfetch`; check `UM_NO_FASTFETCH`; it's skipped when `TERM` is `dumb`/`linux` or the window is under 70 columns |
| Greeting is too noisy | `export UM_NO_FASTFETCH=1` in `~/.zshrc.local` |
| Prompt didn't change after switching theme | Open a new shell — the config is read at startup |
| Everything is slow under `/mnt/c` | Move the repo and your projects under `~/` — cross-OS I/O is 10-20× slower |
| Login shell is still bash | `chsh -s $(command -v zsh)`, then log out and back in |
| WSL networking changes had no effect | `wsl --shutdown` from PowerShell, then reopen |

Every phase has a checkpoint you can run on its own — `bash tests/03_shell.sh`,
`bash tests/12_fastfetch.sh`, and so on. `bash tests/99_smoke.sh` runs them all.
