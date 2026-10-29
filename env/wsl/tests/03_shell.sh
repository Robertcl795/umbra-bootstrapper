#!/usr/bin/env bash
set -euo pipefail

# ADR 0004: fish is installed only when it is the chosen shell.
if [ "${UM_SHELL:-zsh}" = "fish" ] && ! command -v fish >/dev/null 2>&1; then
  echo "fish not installed." >&2
  exit 1
fi
if ! command -v zsh >/dev/null 2>&1; then
  echo "zsh not installed." >&2
  exit 1
fi

if [ "${UM_SHELL:-zsh}" = "fish" ]; then
  fish -lc "echo ok" >/dev/null
fi
zsh -lic "echo ok" >/dev/null

# The config/zsh modules must all be loaded: aliases (ll), the plugin
# loader (zplugin-update) and the git module (gst + its friends).
zsh -lic "type ll >/dev/null && type zplugin-update >/dev/null" \
  || { echo "zsh did not load the config/zsh modules." >&2; exit 1; }

# Git aliases (config/zsh/git.zsh) — check the full set the docs promise, in
# a single shell so the check stays fast. The list has to reach zsh as one
# line: a newline inside the `for` word list is a parse error, and a parse
# error would produce empty output and silently "pass".
GIT_ALIASES="gst gss ga gaa gap grs grst gc gcm gca gcan gcf gco gcob gsw gswc gswd gb gba gbd gbD gbv gbr gbclean gd gds gdw gl glog gadog gf gpl gp gpu gpf gsta gstp gstl grb grbi grbc grba gwt"
if ! missing="$(zsh -lic "for a in $GIT_ALIASES; do type \$a >/dev/null 2>&1 || print -r -- \$a; done")"; then
  echo "zsh failed while checking git aliases (see the error above)." >&2
  exit 1
fi
if [ -n "$missing" ]; then
  echo "Missing git aliases (expected from config/zsh/git.zsh): $(echo "$missing" | tr '\n' ' ')" >&2
  exit 1
fi

# The aliases must complete like the git subcommand they wrap: compdef has
# to exist (compinit ran in core.zsh) and each alias must be registered
# against the _git completion function.
uncompleted="$(zsh -lic 'for a in gst gc gco gcob gsw gswc gb gbD; do [[ ${_comps[$a]} == _git ]] || print -r -- $a; done')"
if [ -n "$uncompleted" ]; then
  echo "Git aliases without completion: $(echo "$uncompleted" | tr '\n' ' ')" >&2
  exit 1
fi

# Plugins (syntax highlighting, autosuggestions, etc.) must be present
plugdir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
for p in zsh-autosuggestions fast-syntax-highlighting zsh-history-substring-search zsh-vi-mode; do
  if [ ! -d "$plugdir/$p" ]; then
    echo "Missing zsh plugin: $p (expected in $plugdir)" >&2
    exit 1
  fi
done

# The default login shell should be zsh (unless fish was chosen)
if [ "${UM_SHELL:-zsh}" = "zsh" ]; then
  login_shell="$(getent passwd "$USER" | cut -d: -f7)"
  case "$login_shell" in
    */zsh) : ;;
    *) echo "Default shell is $login_shell, expected zsh." >&2; exit 1 ;;
  esac
fi
