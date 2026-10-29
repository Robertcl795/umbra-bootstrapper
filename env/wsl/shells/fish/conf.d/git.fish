# Git aliases — fish mirror of config/zsh/git.zsh. Keep the two in sync.
#
# `alias` in fish defines a function, so completions have to be inherited
# explicitly (see the bottom of this file).

# `return` in a sourced file stops this file only — `exit` would take the
# whole shell down with it.
type -q git; or return

# Status & staging
alias gst 'git status'
alias gss 'git status --short --branch'
alias ga 'git add'
alias gaa 'git add --all'
alias gap 'git add --patch'
alias grs 'git restore'
alias grst 'git restore --staged'

# Commit
alias gc 'git commit -v'
alias gcm 'git commit -v -m'
alias gca 'git commit -v --amend'
alias gcan 'git commit -v --amend --no-edit'
alias gcf 'git commit --fixup'

# Checkout / switch
alias gco 'git checkout'
alias gcob 'git checkout -b'
alias gsw 'git switch'
alias gswc 'git switch -c'
alias gswd 'git switch --detach'

# Branch
alias gb 'git branch'
alias gba 'git branch --all'
alias gbd 'git branch -d'
alias gbD 'git branch -D'
alias gbv 'git branch -vv'

# Diff & log
alias gd 'git diff'
alias gds 'git diff --staged'
alias gdw 'git diff --word-diff'
alias glog 'PAGER="less -F -X" git log'
alias gadog 'PAGER="less -F -X" git log --all --decorate --oneline --graph'
alias gl 'PAGER="less -F -X" git log --oneline --graph --decorate -20'

# Remote
alias gf 'git fetch --all --prune'
alias gpl 'git pull --rebase --autostash'
alias gp 'git push'
alias gpu 'git push -u origin HEAD'
alias gpf 'git push --force-with-lease'

# Stash / rebase / worktree
alias gsta 'git stash push'
alias gstp 'git stash pop'
alias gstl 'git stash list'
alias grb 'git rebase'
alias grbi 'git rebase -i'
alias grbc 'git rebase --continue'
alias grba 'git rebase --abort'
alias gwt 'git worktree'

# Branches by most recent commit (newest last, nearest the prompt).
function gbr --description 'List local branches by commit date'
    git for-each-ref --sort=committerdate refs/heads/ \
        --format='%(color:cyan)%(committerdate:short)%(color:reset) %(color:bold white)%(refname:short)%(color:reset) %(contents:subject) %(color:dim)%(authorname)%(color:reset)'
end

# Delete every local branch already merged into the default branch.
function gbclean --description 'Delete local branches merged into the default branch'
    set -l base (string replace 'origin/' '' (git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null))
    test -n "$base"; or set base main
    git branch --merged $base \
        | string trim \
        | string match -v -r '^\*|^(\*\s*)?('$base'|master|main|develop)$' \
        | xargs -r git branch -d
end

# Completions: make each alias complete like the git subcommand it wraps.
for pair in gst/status gss/status ga/add gaa/add gap/add grs/restore \
        grst/restore gc/commit gcm/commit gca/commit gcan/commit gcf/commit \
        gco/checkout gcob/checkout gsw/switch gswc/switch gswd/switch \
        gb/branch gba/branch gbd/branch gbD/branch gbv/branch \
        gd/diff gds/diff gdw/diff gl/log glog/log gadog/log \
        gf/fetch gpl/pull gp/push gpu/push gpf/push \
        gsta/stash gstp/stash gstl/stash grb/rebase grbi/rebase \
        grbc/rebase grba/rebase gwt/worktree
    set -l parts (string split '/' $pair)
    complete -c $parts[1] -w "git $parts[2]"
end
