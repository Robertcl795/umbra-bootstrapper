# Shell greeting: fastfetch on every new interactive shell.
# fish calls fish_greeting once per interactive session, so overriding it
# is all that's needed — no interactive/tty guard of our own.
#
# Opt out with `set -Ux UM_NO_FASTFETCH 1`.

function fish_greeting --description 'fastfetch banner'
    test -z "$UM_NO_FASTFETCH"; or return
    type -q fastfetch; or return
    test -z "$NVIM$VIM"; or return

    # Below ~70 columns the logo and info block stop fitting side by side.
    if test (tput cols 2>/dev/null; or echo 80) -lt 70
        fastfetch --logo none 2>/dev/null
    else
        fastfetch 2>/dev/null
    end
end
