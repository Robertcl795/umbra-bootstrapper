# Git aliases.
#
# Deliberately hand-rolled instead of pulling in oh-my-zsh's git plugin:
# that plugin brings ~150 aliases (and the omz framework loader) for the
# dozen we actually use, and half of them shadow other tools (gp, gm, gk).
# Here every alias is one line, greppable, and completes like the command
# it wraps.
#
# Naming follows the omz convention (g<verb><modifier>) so muscle memory
# transfers both ways.

command -v git >/dev/null 2>&1 || return 0

# =========================================================
# Status & staging
# =========================================================

alias gst='git status'
alias gss='git status --short --branch'   # dense one-line-per-file view
alias ga='git add'
alias gaa='git add --all'
alias gap='git add --patch'               # stage hunk by hunk
alias grs='git restore'
alias grst='git restore --staged'         # unstage, keep working-tree changes

# =========================================================
# Commit
# =========================================================

alias gc='git commit -v'                  # -v shows the diff in the editor
alias gcm='git commit -v -m'
alias gca='git commit -v --amend'
alias gcan='git commit -v --amend --no-edit'
alias gcf='git commit --fixup'            # pairs with: git rebase -i --autosquash

# =========================================================
# Checkout / switch
# =========================================================

# checkout: still the right tool for restoring paths and detached HEADs
alias gco='git checkout'
alias gcob='git checkout -b'

# switch: branch-only, safer than checkout (won't silently overwrite files)
alias gsw='git switch'
alias gswc='git switch -c'
alias gswd='git switch --detach'
alias gsw-='git switch -'                 # back to the previous branch

# =========================================================
# Branch
# =========================================================

alias gb='git branch'
alias gba='git branch --all'
alias gbd='git branch -d'                 # safe delete: refuses if unmerged
alias gbD='git branch -D'                 # force delete
alias gbv='git branch -vv'                # with upstream + last commit

# Branches by most recent commit, newest last (so the freshest stays next
# to the prompt). Columns: date, branch, subject, author.
gbr() {
  git for-each-ref --sort=committerdate refs/heads/ \
    --format='%(color:cyan)%(committerdate:short)%(color:reset) %(color:bold white)%(refname:short)%(color:reset) %(contents:subject) %(color:dim)%(authorname)%(color:reset)'
}

# Delete every local branch already merged into the default branch.
gbclean() {
  local base
  base="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  base="${base#origin/}"
  base="${base:-main}"
  git branch --merged "$base" \
    | grep -vE "^\*|^\s*(${base}|master|main|develop)$" \
    | xargs -r git branch -d
}

# =========================================================
# Diff & log
# =========================================================

alias gd='git diff'
alias gds='git diff --staged'
alias gdw='git diff --word-diff'

# -F: quit if the output fits one screen. -X: don't wipe it on exit.
alias glog='PAGER="less -F -X" git log'
alias gadog='PAGER="less -F -X" git log --all --decorate --oneline --graph'
alias gl='PAGER="less -F -X" git log --oneline --graph --decorate -20'

# =========================================================
# Remote
# =========================================================

alias gf='git fetch --all --prune'
alias gpl='git pull --rebase --autostash'
alias gp='git push'
alias gpu='git push -u origin HEAD'       # push a new branch and track it
alias gpf='git push --force-with-lease'   # never --force: refuses to clobber

# =========================================================
# Stash / rebase / worktree
# =========================================================

alias gsta='git stash push'
alias gstp='git stash pop'
alias gstl='git stash list'
alias grb='git rebase'
alias grbi='git rebase -i'
alias grbc='git rebase --continue'
alias grba='git rebase --abort'
alias gwt='git worktree'

# =========================================================
# Completion
# =========================================================

# Teach the completion system that each alias is really `git <subcommand>`,
# so `gco <TAB>` offers branches and `gbD <TAB>` offers local branches.
# Runs after compinit (sourced from zshrc in that order); the guard keeps
# a compinit-less shell (e.g. `zsh -f`) from erroring out.
if (( $+functions[compdef] )); then
  compdef _git gst=git-status     gss=git-status
  compdef _git ga=git-add         gaa=git-add        gap=git-add
  compdef _git grs=git-restore    grst=git-restore
  compdef _git gc=git-commit      gcm=git-commit     gca=git-commit
  compdef _git gcan=git-commit    gcf=git-commit
  compdef _git gco=git-checkout   gcob=git-checkout
  compdef _git gsw=git-switch     gswc=git-switch    gswd=git-switch
  compdef _git gb=git-branch      gba=git-branch     gbd=git-branch
  compdef _git gbD=git-branch     gbv=git-branch
  compdef _git gd=git-diff        gds=git-diff       gdw=git-diff
  compdef _git gl=git-log         glog=git-log       gadog=git-log
  compdef _git gf=git-fetch       gpl=git-pull
  compdef _git gp=git-push        gpu=git-push       gpf=git-push
  compdef _git gsta=git-stash     gstp=git-stash     gstl=git-stash
  compdef _git grb=git-rebase     grbi=git-rebase    grbc=git-rebase
  compdef _git grba=git-rebase    gwt=git-worktree
fi
