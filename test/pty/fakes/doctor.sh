#!/usr/bin/env bash
# Fake doctor (UM_SETUP_DOCTOR).
# Like finish.sh, the doctor must get the selection, or it checks components nobody chose.
[ "${UM_COMPONENTS:-}" = "shell,prompt" ] || { echo "doctor: UM_COMPONENTS is '${UM_COMPONENTS:-}', want shell,prompt"; exit 1; }
echo "ok 03_shell"
echo "ok 04_prompt"
