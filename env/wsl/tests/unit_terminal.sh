#!/usr/bin/env bash
# unit_terminal.sh — the Windows side of the theme (ADR 0043, G-B2): the Windows Terminal fragment,
# the per-user Nerd Font and the PowerShell prompt block, each written and removed. %LOCALAPPDATA%,
# $PROFILE, reg.exe, winget.exe, powershell.exe and umbra-setup are fakes; nothing on Windows is
# touched. Where powershell.exe is reachable, the block is also parsed by PowerShell itself.
# shellcheck disable=SC2016,SC1091,SC2034,SC2317,SC2329 # fetch_font is called by terminal.sh (SC2317 in shellcheck < 0.11)
set -uo pipefail

TESTS="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd -- "$TESTS/.." && pwd)"
fails=0
pass=0
expect() {
  if (eval "$2"); then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1"; fails=$((fails + 1)); fi
}

real_distro="${WSL_DISTRO_NAME:-}" # before the fakes set it
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/la" "$t/bin" "$t/docs/WindowsPowerShell" "$t/docs/PowerShell" "$t/font"
export UM_WIN_LOCALAPPDATA_U="$t/la" UM_WIN_LOCALAPPDATA_W='C:\Users\t\AppData\Local'
export UM_WIN_PROFILES="$t/docs/WindowsPowerShell/Microsoft.PowerShell_profile.ps1
$t/docs/PowerShell/Microsoft.PowerShell_profile.ps1"
export UM_SETUP_BIN="$t/bin/umbra-setup" UM_THEME=void WSL_DISTRO_NAME=archlinux UM_ENV_DIR="$ENV_DIR"
log="$t/calls"
printf '#!/usr/bin/env bash\necho "reg.exe $*" >>%q\n' "$log" >"$t/bin/reg.exe"
# winget show answers with UM_FAKE_LATEST (the latest stable winget knows); upgrade fails with
# UM_FAKE_UPGRADE_RC (winget 1.29 here: "No installed package found" for a listed PowerShell).
printf '#!/usr/bin/env bash\necho "winget.exe $*" >>%q\ncase "$1" in\n  show) [ -n "${UM_FAKE_LATEST:-}" ] && printf "Found PowerShell [Microsoft.PowerShell]\\nVersion: %%s\\n" "$UM_FAKE_LATEST" ;;\n  upgrade) exit "${UM_FAKE_UPGRADE_RC:-0}" ;;\nesac\nexit 0\n' "$log" >"$t/bin/winget.exe"
printf '#!/usr/bin/env bash\necho "powershell.exe $*" >>%q\necho "${UM_FAKE_POLICY:-RemoteSigned}"\n' "$log" >"$t/bin/powershell.exe"
printf '#!/usr/bin/env bash\necho "umbra-setup $*" >>%q\nprintf "{\\"profiles\\": [{\\"colorScheme\\": \\"Umbra Void\\", \\"font\\": {\\"face\\": \\"%%s\\"}}], \\"schemes\\": [{\\"name\\": \\"Umbra Void\\"}]}\\n" "$4"\n' "$log" >"$t/bin/umbra-setup"
chmod +x "$t/bin"/*
# Only the fakes and the base system: this Windows may have its own starship, reg.exe and winget.
real_ps=$(command -v powershell.exe || true)
export PATH="$t/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin"
: >"$t/font/JetBrainsMonoNerdFont-Regular.ttf"

# The script defines its functions when sourced without arguments. fetch_font is the network:
# here it puts the four files in the directory it is given.
source "$ENV_DIR/install/terminal.sh"
fetch_font() {
  local f
  for f in Regular Bold Italic BoldItalic; do echo "ttf $f" >"$1/JetBrainsMonoNerdFont-$f.ttf"; done
}
frag="$t/la/Microsoft/Windows Terminal/Fragments/Umbra/umbra.json"
fonts="$t/la/Microsoft/Windows/Fonts"
p51="$t/docs/WindowsPowerShell/Microsoft.PowerShell_profile.ps1"
p7="$t/docs/PowerShell/Microsoft.PowerShell_profile.ps1"

echo "# terminal: fragment and font"
: >"$log"
out="$(terminal_install 2>&1)"
expect "the fragment is written where Windows Terminal reads fragments" '[ -s "$frag" ]'
expect "it comes from umbra-setup, for the theme, with the Nerd Font" 'grep -q "umbra-setup --wt-fragment void --wt-font JetBrainsMono Nerd Font" "$log" && grep -q "JetBrainsMono Nerd Font" "$frag"'
expect "four font files in the per-user Fonts folder" '[ "$(command ls "$fonts" | grep -c "^JetBrainsMonoNerdFont-.*\.ttf$")" = 4 ]'
expect "each one registered under HKCU, pointing at its Windows path" '[ "$(grep -c "reg.exe add HKCU\\\\Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\Fonts /v JetBrainsMono Nerd Font .* (TrueType) /t REG_SZ /d C:\\\\Users\\\\t\\\\AppData\\\\Local\\\\Microsoft\\\\Windows\\\\Fonts\\\\JetBrainsMonoNerdFont-.*\.ttf /f" "$log")" = 4 ]'
expect "no admin path: nothing under HKLM or C:\\Windows\\Fonts" '! grep -qi "HKLM\|Windows\\\\Fonts\\\\[^J]" "$log"'
: >"$log"
terminal_install >/dev/null 2>&1
expect "a second run keeps the font (no registry writes) and rewrites the fragment" '! grep -q "reg.exe add" "$log" && [ -s "$frag" ]'

echo "# terminal: the user's profiles.defaults (read, never written; operator: tell the user only)"
wtset="$t/la/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
mkdir -p "$(dirname "$wtset")"
expect "no settings.json: no hint" '[[ $out != *"profiles.defaults"* ]]'
cat >"$wtset" <<'J'
{
    // a comment, as Windows Terminal writes them
    "defaultProfile": "{x}",
    "profiles": {
        "defaults": {
            "colorScheme": "tokyonight",
            "font": { "face": "FiraCode Nerd Font", "size": 11 }
        },
        "list": [ { "name": "Ubuntu", "colorScheme": "Campbell" } ]
    },
    "schemes": [ { "name": "tokyonight" } ]
}
J
cp "$wtset" "$t/wtset.before"
out="$(terminal_install 2>&1)"
expect "defaults with a scheme and a font: both are named, with where to change the Umbra profile" '[[ $out == *"profiles.defaults"* && $out == *"tokyonight"* && $out == *"FiraCode Nerd Font"* && $out == *"Umbra Void"* && $out == *"Umbra · archlinux"* ]]'
expect "settings.json is not changed" 'cmp -s "$wtset" "$t/wtset.before"'
sed -i '/"colorScheme": "tokyonight",/d; s/"font": { "face": "FiraCode Nerd Font", "size": 11 }/"opacity": 90/' "$wtset"
out="$(terminal_install 2>&1)"
expect "defaults without scheme or font (a profile's own scheme does not count): no hint" '[[ $out != *"profiles.defaults"* ]]'
rm -rf "$t/la/Packages"

echo "# terminal: the font fails"
rm -rf "$fonts"
fetch_font() { return 1; }
out="$(terminal_install 2>&1)"
expect "the fragment falls back to Cascadia Mono and says so" 'grep -q "Cascadia Mono" "$frag" && [[ $out == *"Cascadia Mono"* ]]'
fetch_font() {
  local f
  for f in Regular Bold Italic BoldItalic; do echo "ttf $f" >"$1/JetBrainsMonoNerdFont-$f.ttf"; done
}
terminal_install >/dev/null 2>&1

echo "# terminal: no umbra-setup"
mv "$t/bin/umbra-setup" "$t/umbra-setup.off"
rm -f "$frag"
out="$(terminal_install 2>&1)"
rc=$?
expect "no fragment, a warning, and the run goes on (exit 0)" '[ ! -e "$frag" ] && [ $rc = 0 ] && [[ $out == *"umbra-setup"* ]]'
mv "$t/umbra-setup.off" "$t/bin/umbra-setup"
terminal_install >/dev/null 2>&1

echo "# doctor: 13_terminal.sh"
expect "passes with the fragment in place" 'bash "$TESTS/13_terminal.sh" 2>/dev/null'
cp "$frag" "$t/frag.bak"
sed -i 's/"colorScheme": "Umbra Void"/"colorScheme": "Neon"/' "$frag"
expect "fails when the profile names a scheme the fragment lacks" '! bash "$TESTS/13_terminal.sh" 2>/dev/null'
rm -f "$frag"
expect "fails when the fragment is missing" '! bash "$TESTS/13_terminal.sh" 2>/dev/null'
expect "warns and passes when the Windows side is out of reach" 'UM_WIN_LOCALAPPDATA_U=/nonexistent bash "$TESTS/13_terminal.sh" 2>&1 | grep -q "not reachable"'
cp "$t/frag.bak" "$frag"

echo "# terminal: remove"
: >"$log"
terminal_remove >/dev/null 2>&1
expect "the fragment folder is gone" '[ ! -e "$t/la/Microsoft/Windows Terminal/Fragments/Umbra" ]'
expect "the font files are gone and each registry value is deleted" '[ -z "$(command ls "$fonts" 2>/dev/null)" ] && [ "$(grep -c "reg.exe delete HKCU.*/v JetBrainsMono Nerd Font .* (TrueType) /f" "$log")" = 4 ]'

echo "# pwsh: the prompt block"
printf 'Set-Alias ll Get-ChildItem\r\n' >"$p51"
: >"$log"
out="$(pwsh_install 2>&1)"
expect "starship through winget, exact id, from the winget source" 'grep -q "winget.exe install --id Starship.Starship --exact --source winget" "$log"'
expect "the variant's starship.toml, in a file of Umbra's own" 'cmp -s "$t/la/umbra/starship.toml" "$ENV_DIR/../.chezmoitemplates/starship/void.toml"'
expect "one marked block in each profile; the user's lines kept" '[ "$(grep -c ">>> umbra prompt >>>" "$p51")" = 1 ] && [ "$(grep -c ">>> umbra prompt >>>" "$p7")" = 1 ] && grep -q "Set-Alias ll" "$p51"'
expect "the block points STARSHIP_CONFIG at that file and runs starship init" 'grep -q "STARSHIP_CONFIG" "$p7" && grep -qF "Invoke-Expression (&starship init powershell)" "$p7"'
pwsh_install >/dev/null 2>&1
expect "a second run leaves one block" '[ "$(grep -c ">>> umbra prompt >>>" "$p51")" = 1 ] && [ "$(grep -c "<<< umbra prompt <<<" "$p51")" = 1 ]'
expect "the execution policy is read, never set" 'grep -q "Get-ExecutionPolicy" "$log" && ! grep -qi "Set-ExecutionPolicy" "$log"'
out="$(UM_FAKE_POLICY=Restricted pwsh_install 2>&1)"
expect "under Restricted it says the profile will not load and names the command for the user" '[[ $out == *Restricted* && $out == *"Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"* ]]'

expect "doctor 14_pwsh.sh passes with Umbra's starship.toml" 'bash "$TESTS/14_pwsh.sh" 2>/dev/null'

echo "# pwsh: remove"
pwsh_remove >/dev/null 2>&1
expect "the block is gone, the user's lines stay byte for byte" '[ "$(cat "$p51")" = "$(printf "Set-Alias ll Get-ChildItem\r")" ] && ! grep -q umbra "$p7"'
expect "Umbra's starship.toml is gone" '[ ! -e "$t/la/umbra/starship.toml" ]'
expect "doctor 14_pwsh.sh then fails" '! bash "$TESTS/14_pwsh.sh" 2>/dev/null'

echo "# pwsh7: PowerShell 7 from winget (ADR 0006 exception: the latest stable, verified by winget)"
# UM_WIN_PWSH is the pwsh.exe the script finds; the fake answers \$PSVersionTable with UM_FAKE_PWSH_V.
fakepwsh="$t/bin/pwsh-fake.exe"
printf '#!/usr/bin/env bash\necho "pwsh.exe $*" >>%q\necho "${UM_FAKE_PWSH_V:-7.4.6}"\n' "$log" >"$fakepwsh"
chmod +x "$fakepwsh"
: >"$log"
out="$(UM_WIN_PWSH=none pwsh7_install 2>&1)"
expect "no pwsh.exe: winget installs Microsoft.PowerShell, exact id, source winget, silent" \
  'grep -qx "winget.exe install --id Microsoft.PowerShell --exact --source winget --accept-package-agreements --accept-source-agreements --silent" "$log"'
: >"$log"
UM_WIN_PWSH="$fakepwsh" pwsh7_install >/dev/null 2>&1
expect "pwsh 7 found, latest unknown: winget upgrades it instead" \
  'grep -qx "winget.exe upgrade --id Microsoft.PowerShell --exact --source winget --accept-package-agreements --accept-source-agreements --silent" "$log" && ! grep -q "winget.exe install" "$log"'
: >"$log"
out="$(UM_WIN_PWSH="$fakepwsh" UM_FAKE_PWSH_V=7.6.9 UM_FAKE_LATEST=7.6.9.0 pwsh7_install 2>&1)"
expect "pwsh 7.6.9 and winget's latest 7.6.9.0: no upgrade, and it says so" \
  '! grep -q "winget.exe upgrade" "$log" && grep -q "7.6.9 is the latest stable" <<<"$out"'
: >"$log"
out="$(UM_WIN_PWSH="$fakepwsh" UM_FAKE_PWSH_V=7.4.6 UM_FAKE_LATEST=7.6.9.0 UM_FAKE_UPGRADE_RC=1 pwsh7_install 2>&1)"
expect "an older 7 that winget cannot upgrade: a warning with the command, not a silent pass" \
  'grep -q "winget.exe upgrade" "$log" && grep -q "PowerShell 7.4.6 is installed; the latest stable is 7.6.9" <<<"$out" && grep -q "winget install --id Microsoft.PowerShell --source winget" <<<"$out"'
: >"$log"
UM_WIN_PWSH="$fakepwsh" UM_FAKE_PWSH_V=6.2.7 pwsh7_install >/dev/null 2>&1
expect "an older pwsh (6.x): winget installs 7" 'grep -q "winget.exe install --id Microsoft.PowerShell" "$log"'
expect "doctor 15_pwsh7.sh passes with pwsh 7.x" 'UM_WIN_PWSH="$fakepwsh" bash "$TESTS/15_pwsh7.sh" 2>/dev/null'
expect "doctor 15_pwsh7.sh fails with 6.x or none" \
  '! UM_WIN_PWSH="$fakepwsh" UM_FAKE_PWSH_V=6.2.7 bash "$TESTS/15_pwsh7.sh" 2>/dev/null && ! UM_WIN_PWSH=none bash "$TESTS/15_pwsh7.sh" 2>/dev/null'
expect "pwsh_exe: a pwsh 7 installed in this run is found off PATH (UM_WIN_PWSH)" '[ "$(UM_WIN_PWSH="$fakepwsh" pwsh_exe)" = "$fakepwsh" ]'

# PowerShell parses the block (only where the real powershell.exe is reachable).
if [ -n "$real_ps" ]; then
  pwsh_block >"$t/block.ps1"
  # wslpath names the distro from WSL_DISTRO_NAME, which the fakes above changed.
  win=$(WSL_DISTRO_NAME="$real_distro" wslpath -w "$t/block.ps1" 2>/dev/null || true)
  errs=$(cd /mnt/c 2>/dev/null && "$real_ps" -NoProfile -Command "\$e = \$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$win', [ref]\$null, [ref]\$e); \$e.Count" </dev/null | tr -d '\r')
  expect "Windows PowerShell parses the block without errors" '[ "$errs" = 0 ]'
fi

echo "unit_terminal: $pass ok, $fails failed"
[ "$fails" = 0 ]
