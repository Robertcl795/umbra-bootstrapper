"""Real-install gate of umbra-setup (setup-tui G5): run INSIDE a disposable WSL distro by the
umbrella's scripts/wsl-gate-setup.sh. It drives the real binary through a real install of
packages, shell and prompt (sudo password typed on the terminal, the doctor at the end), then a
second run that must start from the stored selection and pass again.

Usage: python3 -I gate_real.py <checkout> <password-file> [user|root|rerun]
  user   a regular user: a real install, then a re-run (Ubuntu with its user)
  root   a fresh distro as root: the account screen, stage 1, the restart point, where enter leaves
         WSL: umbra-setup terminates the distro, which ends this gate too (its output is in RAW)
  root-check  after that restart: the checks of the root run, on RAW (Arch)
  resume after the restart: `umbra bootstrap resume` in a terminal opens umbra-setup --resume and
         stage 2 runs on its run screen to done (Arch)
  rerun  after stage 2: umbra-setup opens with the stored selection and installs again
Prints one line per check and "gate-real: N ok, M failed"; exits 1 on any failure.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import driver  # noqa: E402

ENTER, DOWN, SPACE = "\r", "\x1b[B", " "
# "assword" matches both prompts: sudo's "[sudo] password for <user>:" and sudo-rs's
# "[sudo: authenticate] Password:" (Ubuntu 26.04 ships sudo-rs 0.2.13, seen 2026-11-05).
results = []


def check(name, cond, detail=""):
    results.append(bool(cond))
    print(("  ok   " if cond else "  FAIL ") + name, flush=True)
    if not cond and detail:
        print("       " + detail.replace("\n", "\n       ")[-3000:], flush=True)


def env_for(checkout):
    return {
        "PATH": os.environ["PATH"], "HOME": os.environ["HOME"], "USER": os.environ.get("USER", "umbra"),
        "TERM": "xterm-256color", "COLORTERM": "truecolor", "COLUMNS": "100", "LINES": "30",
        "LANG": "C.UTF-8", "UM_LANG": "en", "UM_THEME": "umbra", "UM_AI_ACCESS": "0", "UM_REDUCED_MOTION": "1",
        "WSL_DISTRO_NAME": os.environ.get("WSL_DISTRO_NAME", ""),
    }


T = "title:Umbra setup · "  # steps wait on umbra-setup's window title (driver.py)


def titled(raw, name):
    """The window title "Umbra setup · <name>" was set at some point of the run."""
    return ("\x1b]2;Umbra setup · " + name).encode() in raw or ("\x1b]0;Umbra setup · " + name).encode() in raw


# n clears; the cursor stays on packages: packages, shell, prompt.
PICK = [(T + "components 9/9", "n"), (T + "components 0/9", SPACE), (T + "components 1/9", DOWN + SPACE),
        (T + "components 2/9", DOWN + SPACE), (T + "components 3/9", ENTER), (T + "theme umbra", ENTER)]


def user_runs(argv, env, password):
    steps = [(T + "scan ready", ENTER), (T + "profile", ENTER)] + PICK + [
        (T + "review install", ENTER), ("assword", password + "\r"), (T + "done", ENTER)]
    code, text, raw = driver.run(argv, steps, env, timeout=2400, settle=0.4)
    check("run 1: real install of packages, shell, prompt through umbra-setup; doctor passes; exit 0",
          code == 0 and titled(raw, "done"), text[-4000:])
    check("run 1: the run screen was shown", titled(raw, "run"), text[-3000:])
    rerun(argv, env, password)


def rerun(argv, env, password):
    # The stored selection (3 of 9) opens the components screen. sudo keeps its timestamp per
    # terminal, and this is a new one, so it asks again.
    steps = [(T + "scan ready", ENTER), (T + "profile", ENTER), (T + "components 3/9", ENTER),
             (T + "theme umbra", ENTER), (T + "review install", ENTER), ("assword", password + "\r"), (T + "done", ENTER)]
    code, text, raw = driver.run(argv, steps, env, timeout=1800, settle=0.4)
    check("re-run: opens with the stored selection (components 3/9)", titled(raw, "components 3/9"), text[-3000:])
    check("re-run: passes again, exit 0", code == 0 and titled(raw, "done"), text[-4000:])


RAW = "/root/.gate-root.raw"  # the root run's terminal output, written as it arrives


def root_run(argv, env, password):
    # A fresh distro as root: the account screen, stage 1, the restart point; enter there leaves
    # WSL. If this gate is still alive afterwards, the distro was not terminated.
    steps = [(T + "scan ready", ENTER), (T + "profile", ENTER),
             (T + "account user", "umbra\t" + password + "\t" + password + "\r")] + PICK + [
        (T + "review install", ENTER), (T + "restart", ENTER)]
    code, text, raw = driver.run(argv, steps, env, timeout=2400, settle=0.4, tee=RAW)
    check("root: enter on the restart screen terminated the distro (this line must not print)", False,
          f"exit {code}\n" + text[-3000:])


def root_check(_argv, _env, password):
    # Started again after the root run's distro was terminated: its output is in RAW.
    raw = open(RAW, "rb").read()
    text = driver.clean(raw)
    check("root: account screen, stage 1 through umbra-setup, the restart point",
          titled(raw, "account user") and titled(raw, "restart"), text[-4000:])
    check("root: the password is never drawn", password.encode() not in raw, "the password appeared in the output")


def resume_run(_argv, env, _password):
    # Stage 2 as the new user, in a terminal: the wrapper opens the copy stage 1 left in
    # ~/.local/bin; sudo is passwordless until finish.sh removes the temporary rule.
    copy = os.path.join(os.environ["HOME"], ".local", "bin", "umbra-setup")
    check("resume: stage 1 left a verified umbra-setup in ~/.local/bin", os.access(copy, os.X_OK), copy)
    steps = [(T + "run", ""), (T + "done", ENTER)]
    code, text, raw = driver.run(["umbra", "bootstrap", "resume"], steps, env, timeout=2400, settle=0.4)
    check("resume: stage 2 on umbra-setup's run screen to done, exit 0",
          code == 0 and titled(raw, "run") and titled(raw, "done") and b"Stage 2" in raw, text[-4000:])
    check("resume: finish.sh's doctor is the doctor row", b"doctor" in raw.lower() and titled(raw, "done"), text[-2000:])


def main():
    checkout, pwfile = sys.argv[1], sys.argv[2]
    mode = sys.argv[3] if len(sys.argv) > 3 else "user"
    password = open(pwfile).read().strip()
    argv = [os.path.join(checkout, "build", "umbra-setup"), "--env-dir", os.path.join(checkout, "env", "wsl")]
    {"user": user_runs, "rerun": rerun, "root": root_run, "root-check": root_check, "resume": resume_run}[mode](argv, env_for(checkout), password)
    ok = sum(results)
    print(f"gate-real: {ok} ok, {len(results) - ok} failed", flush=True)
    sys.exit(0 if ok == len(results) else 1)


if __name__ == "__main__":
    main()
