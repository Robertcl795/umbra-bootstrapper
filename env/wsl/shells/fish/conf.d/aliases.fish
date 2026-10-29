# General aliases — fish mirror of config/zsh/aliases.zsh.
# Git aliases live in git.fish.

if type -q eza
    alias ls 'eza --icons --group-directories-first'
    alias ll 'eza -lh --icons --git --group-directories-first'
    alias la 'eza -lah --icons --git --group-directories-first'
    alias tree 'eza --tree --icons'
end

if type -q bat
    alias cat 'bat'
end

if type -q rg
    alias grep 'rg --color=auto'
end

if type -q duf
    alias df 'duf'
else
    alias df 'df -h'
end

alias diff 'diff --color=auto'
alias vim 'nvim'

# Modern CLI stack
type -q lazygit; and alias lg 'lazygit'
type -q lazydocker; and alias ld 'lazydocker'
type -q fastfetch; and alias ff 'fastfetch'

# yazi with directory-follow: quitting yazi leaves you in the last dir.
if type -q yazi
    function y --description 'yazi, following the directory you quit in'
        set -l tmp (mktemp -t yazi-cwd.XXXXXX)
        yazi $argv --cwd-file="$tmp"
        set -l cwd (cat -- "$tmp")
        if test -n "$cwd" -a "$cwd" != "$PWD"
            cd -- "$cwd"
        end
        rm -f -- "$tmp"
    end
    alias lf 'y'
end
