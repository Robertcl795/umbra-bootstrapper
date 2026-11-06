#!/usr/bin/env bash
# Fake install/shell/default.sh (UM_SETUP_DEFAULT): the login shell is bash; a change is logged
# to $FAKE_DIR/default.log, never made.
case "$1" in
  --status) echo "login=/bin/bash" ;;
  --shell) echo "default.sh --shell $2" >>"$FAKE_DIR/default.log"; echo "[INFO] Your login shell is now $2 (/usr/bin/$2); it applies to new sessions." ;;
  --wt-pwsh7) echo "default.sh --wt-pwsh7" >>"$FAKE_DIR/default.log" ;;
esac
