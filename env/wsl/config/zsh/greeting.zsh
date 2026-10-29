# Shell greeting: fastfetch on every new interactive shell (new tab, new
# window, new zellij pane). Sourced last from shells/zsh/zshrc.
#
# Opt out permanently with `export UM_NO_FASTFETCH=1` in ~/.zshrc.local,
# or for one shell with `UM_NO_FASTFETCH=1 zsh`.

[[ -o interactive ]] || return 0
[ -t 1 ] || return 0
[ -z "${UM_NO_FASTFETCH:-}" ] || return 0
command -v fastfetch >/dev/null 2>&1 || return 0

# Terminals that render a shell but aren't a place for a banner:
# nvim's :terminal, dumb TERMs, and anything without a real screen size.
[ -z "${NVIM:-}${VIM:-}${VIMRUNTIME:-}" ] || return 0
[[ "${TERM:-dumb}" != "dumb" && "${TERM:-}" != "linux" ]] || return 0

# Below ~70 columns the logo and the info block stop fitting side by side;
# drop the logo rather than let fastfetch wrap into a mess.
if (( ${COLUMNS:-80} < 70 )); then
  fastfetch --logo none 2>/dev/null
else
  fastfetch 2>/dev/null
fi
