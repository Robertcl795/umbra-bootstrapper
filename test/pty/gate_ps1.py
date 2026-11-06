"""G-A2 gate of install.ps1 (ADR 0042): run OUTSIDE the scratch distro, by the umbrella's
scripts/wsl-gate-ps1.sh. It drives powershell.exe on a pty: install.ps1 is read and piped to
Invoke-Expression (as `irm | iex` does), installs the distro with wsl --install --no-launch, runs
stage 1 (a local build, through UM_PS1_STAGE1) on the same terminal, terminates the distro on exit
code 10 and runs `umbra bootstrap resume` as the new default user to done.

Usage: python3 -I gate_ps1.py <install.ps1> <online-name> <distro> <payload (Windows path)> <password-file> <raw-out>
Prints one line per check and "gate-ps1: N ok, M failed"; exits 1 on any failure. The checks
that need the distro afterwards (default user, systemd) are the wrapper's.
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import driver  # noqa: E402
from gate_real import ENTER, PICK, T, check, results, titled  # noqa: E402


def psq(s):
    """A PowerShell single-quoted literal."""
    return "'" + s.replace("'", "''") + "'"


def stage1(online, payload):
    """Stage 1 inside the new distro, as root: what install.sh's piped part does (git), the local
    checkout as a git repo (stage 1 clones the checkout it runs from), then the local build.
    No double quotes (install.ps1 passes it to wsl.exe)."""
    if online == "archlinux":
        deps = ("pacman-key --init >/dev/null 2>&1; pacman-key --populate archlinux >/dev/null 2>&1; "
                "pacman -Syu --noconfirm --needed git >/dev/null")
    else:
        deps = "command -v git >/dev/null || { apt-get update -qq && apt-get install -y -qq git >/dev/null; }"
    d = "/root/dev/umbra-bootstrapper"
    return (f"set -e; echo gate: preparing; {deps}; mkdir -p {d}; tar -xzf $(wslpath -u '{payload}') -C {d}; cd {d}; "
            "git init -q; git add -A; git add -f build/umbra-setup; "
            "git -c user.name=gate -c user.email=gate@localhost commit -qm gate; set +e; "
            "export COLORTERM=truecolor UM_LANG=en UM_THEME=umbra UM_AI_ACCESS=0 UM_REDUCED_MOTION=1; "
            f"exec {d}/build/umbra-setup --env-dir {d}/env/wsl")


def main():
    ps1, online, distro, payload, pwfile, rawout = sys.argv[1:7]
    password = open(pwfile).read().strip()
    win_ps1 = subprocess.run(["wslpath", "-w", ps1], capture_output=True, text=True, check=True).stdout.strip()
    command = "; ".join([
        f"$env:UM_PS1_DISTRO = {psq(online)}", f"$env:UM_PS1_DISTRO_NAME = {psq(distro)}",
        f"$env:UM_PS1_STAGE1 = {psq(stage1(online, payload))}",
        f"Get-Content -Raw {psq(win_ps1)} | Invoke-Expression",
        "Write-Host ('gate-ps1-rc=' + $LASTEXITCODE)",
    ])
    env = {"PATH": os.environ["PATH"], "HOME": os.environ["HOME"], "TERM": "xterm-256color",
           "COLUMNS": "100", "LINES": "30", "LANG": "C.UTF-8"}
    steps = [(T + "scan ready", ENTER), (T + "profile", ENTER),
             (T + "account user", "umbra\t" + password + "\t" + password + "\r")] + PICK + [
        (T + "review install", ENTER), (T + "restart", ENTER),
        (T + "run", ""), (T + "done", ENTER), ("gate-ps1-rc=", "")]
    code, text, raw = driver.run(["powershell.exe", "-NoProfile", "-Command", command], steps, env,
                                 timeout=3600, settle=0.4, tee=rawout)
    clean = driver.clean(raw)
    rc = re.search(r"gate-ps1-rc=(-?\d+)", clean)
    check("(a)+(b) WSL checked, the distro installed by wsl --install --no-launch",
          f"installing {online} as {distro}" in clean and f"stage 1 in {distro}" in clean, text[-3000:])
    check("(c) stage 1 on this terminal: account screen through the restart point",
          titled(raw, "account user") and titled(raw, "restart"), text[-3000:])
    check("(c) the restart screen names PowerShell (driver mode)", b"continue in PowerShell" in raw, text[-2000:])
    check("(d) exit code 10 led to the restart", f"restarting {distro}" in clean, text[-2000:])
    after = raw[raw.find(f"stage 2 in {distro}".encode()):] if f"stage 2 in {distro}" in clean else b""
    check("(e) stage 2 on umbra-setup's run screen to done", titled(after, "run") and titled(after, "done"), text[-3000:])
    check("install.ps1 ends with done and $LASTEXITCODE 0",
          "umbra: done" in clean and rc is not None and rc.group(1) == "0", f"exit {code}, rc {rc and rc.group(1)}\n" + text[-2000:])
    check("the password is never drawn", password.encode() not in raw, "the password appeared in the output")
    ok = sum(results)
    print(f"gate-ps1: {ok} ok, {len(results) - ok} failed", flush=True)
    sys.exit(0 if ok == len(results) else 1)


if __name__ == "__main__":
    main()
