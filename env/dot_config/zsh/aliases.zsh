# General aliases (listing, core utils, navigation, editor).
# Git aliases live in git.zsh. Everything is guarded on the tool existing.

# =========================================================
# Listing (eza)
# =========================================================

if command -v eza >/dev/null 2>&1; then
  # Better ls
  alias ls='eza --icons'

  # Detailed listing
  alias ll='eza -lh --icons --git'

  # Detailed listing including hidden files
  alias la='eza -lah --icons --git'

  # Tree view
  alias tree='eza --tree --icons'

  # Reuse ls completions for eza (avoids defining a separate completion function)
  compdef eza=ls 2>/dev/null
fi

# Better cat
if command -v bat >/dev/null 2>&1; then
  alias cat='bat'
fi

# =========================================================
# Core utilities
# =========================================================

if command -v rg >/dev/null 2>&1; then
  alias grep='rg --color=auto'
fi
alias diff='diff --color=auto'
if command -v duf >/dev/null 2>&1; then
  alias df='duf'
else
  alias df='df -h'
fi

# =========================================================
# Navigation
# =========================================================

alias -- -='cd -'  # -- prevents - being parsed as a flag; cd - jumps to previous directory

# Upstream uses lf; we use yazi. Keep the muscle memory working.
alias lf='y'

# yazi with directory-follow: quitting yazi leaves you in the last visited dir
y() {
  local tmp cwd
  tmp="$(mktemp -t yazi-cwd.XXXXXX)"
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd" || return
  fi
  rm -f -- "$tmp"
}

# =========================================================
# Editor
# =========================================================

alias vim='nvim'

# =========================================================
# Modern CLI stack shortcuts
# =========================================================

alias lg='lazygit'
alias ld='lazydocker'
alias ff='fastfetch'
