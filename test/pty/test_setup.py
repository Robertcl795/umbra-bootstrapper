"""PTY tests of umbra-setup (setup-tui ux-spec §8, gate G3): the real binary in a real terminal.

Usage (from the bootstrapper root):  go build -o build/umbra-setup ./cmd/umbra-setup
                                      python3 -I test/pty/test_setup.py
Prints one line per check and "setup-pty: N ok, M failed"; exits 1 on any failure.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import driver  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BIN = os.path.join(ROOT, "build", "umbra-setup")
ENV_DIR = os.path.join(ROOT, "env", "wsl")
FAKES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakes")
ENTER, DOWN, RIGHT, SPACE, CTRL_C = "\r", "\x1b[B", "\x1b[C", " ", "\x03"

results = []


def check(name, cond, detail=""):
    results.append(bool(cond))
    print(("  ok   " if cond else "  FAIL ") + name)
    if not cond and detail:
        print("       " + detail.replace("\n", "\n       ")[-1500:])


ISOLATED = tempfile.mkdtemp(prefix="setup-pty-home-")


def env(**extra):
    # Never the user's chezmoi data or state: a re-run would start from them.
    e = {
        "XDG_CONFIG_HOME": os.path.join(ISOLATED, "config"), "XDG_STATE_HOME": os.path.join(ISOLATED, "state"),
        "PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp"), "TERM": "xterm-256color",
        "COLUMNS": "80", "LINES": "24", "LANG": "C.UTF-8", "UM_LANG": "en", "UM_THEME": "umbra",
        "COLORTERM": "truecolor", "UM_OS": "arch", "UM_IS_WSL": "1", "UM_AI_ACCESS": "1",
        "UM_REDUCED_MOTION": "1", "UM_ENV_DIR": ENV_DIR,
    }
    e.update(extra)
    return {k: v for k, v in e.items() if v is not None}


def walk_to_review():
    return [("enter continue", ENTER), ("Which profile", ENTER), ("of 10 selected", ENTER),
            ("Pick a variant", ENTER), ("[ Install ]", "")]


def f1_defaults_dry_run():
    steps = walk_to_review()[:-1] + [("[ Install ]", RIGHT), ("› [ Dry run ]", ENTER)]
    code, text, raw = driver.run([BIN], steps, env(), timeout=30)
    line = text.split("--- screen ---")[0]
    check("F1 defaults, Dry run: install.sh --dry-run prints the plan (contract C5)",
          code == 0 and "platform=wsl-arch profile=personal components=packages,shell,prompt,nvim,k8s,zellij,lang,fastfetch,wsl,ai-cli,ai-standard,um,vault,ollama" in line, text)
    check("F1 truecolor paints the variant background (OSC 11)", b"\x1b]11;" in raw)
    check("F1 the background is reset on exit (OSC 111)", b"\x1b]111" in raw)


def f2_work_untick_void():
    steps = [("enter continue", ENTER), ("Which profile", DOWN), ("Check your company", ENTER),
             ("of 10 selected", SPACE), ("9 of 10 selected", ENTER),
             ("Pick a variant", RIGHT), ("UM_THEME=void", ENTER), ("[ Install ]", RIGHT), ("› [ Dry run ]", ENTER)]
    code, text, _ = driver.run([BIN], steps, env(), timeout=30)
    check("F2 work, packages unticked, void: install.sh --dry-run agrees", code == 0 and "profile=work components=shell,prompt" in text, text)


def f3_cancel():
    code, text, _ = driver.run([BIN], [("enter continue", ENTER), ("Which profile", CTRL_C)], env(), timeout=20)
    check("F3 ctrl+c before Install: exit 130, nothing installed", code == 130 and "Cancelled. Nothing was installed." in text, text)


def f4_small():
    code, text, _ = driver.run([BIN], [("needs 80×24", "q")], env(COLUMNS="70", LINES="20"))
    check("F4 a 70×20 terminal gets the size message; q leaves", code == 130 and "Terminal is 70×20" in text, text)


def f5_no_tty():
    out = subprocess.run([BIN], env=env(), capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=10)
    check("F5 no terminal: exit 2 and the flags hint", out.returncode == 2 and "needs a terminal" in out.stderr, out.stderr)


def f6_no_color():
    code, text, raw = driver.run([BIN], [("SYSTEM SCAN", "q")], env(NO_COLOR="1"))
    check("F6 NO_COLOR: no color codes and no background", code == 130 and b"38;2;" not in raw and b"\x1b]11;" not in raw, text)


def f7_spanish():
    code, text, _ = driver.run([BIN], [("enter continuar", ENTER), ("¿Qué perfil", "q")], env(UM_LANG="es"), timeout=20)
    check("F7 UM_LANG=es: the screens are in Spanish", code == 130 and "Cancelado. No se instaló nada." in text, text)


def f8_ansi16():
    code, text, raw = driver.run([BIN], [("SYSTEM SCAN", "q")], env(COLORTERM=None))
    check("F8 no COLORTERM: ANSI-16 slots (SGR 30-37), no truecolor", code == 130 and b"38;2;" not in raw and re.search(rb"\x1b\[[0-9;]*3[0-7]m", raw), text)


# ── G4: the run, with a fake install.sh, doctor and sudo ──────────────────────
def run_env(tmp, **extra):
    return env(UM_SETUP_INSTALL=os.path.join(FAKES, "install.sh"), UM_SETUP_DOCTOR=os.path.join(FAKES, "doctor.sh"),
               FAKE_ARGS=os.path.join(tmp, "args"), FAKE_SUDO_LOG=os.path.join(tmp, "sudo.log"),
               XDG_STATE_HOME=os.path.join(tmp, "state"), XDG_CONFIG_HOME=os.path.join(tmp, "config"),
               PATH=os.path.join(FAKES, "bin") + ":" + os.environ["PATH"], **extra)


def to_install():
    # shell and prompt only: n (none), down, space (shell), down, space (prompt)
    return [("enter continue", ENTER), ("Which profile", ENTER), ("of 10 selected", "n"), ("0 of 10 selected", DOWN + SPACE),
            ("1 of 10 selected", DOWN + SPACE), ("2 of 10 selected", ENTER), ("Pick a variant", ENTER), ("[ Install ]", ENTER)]


def g1_run_with_sudo_and_doctor():
    tmp = tempfile.mkdtemp(prefix="setup-pty-")
    steps = to_install() + [("password for tester", "test-password\r"), ("Umbra is set up.", ENTER)]
    code, text, _ = driver.run([BIN], steps, run_env(tmp), timeout=40)
    check("G1 Install asks sudo once on the terminal, runs, passes the doctor, exits 0", code == 0 and "Umbra is set up. " in text, text)
    sudo = open(os.path.join(tmp, "sudo.log")).read() if os.path.exists(os.path.join(tmp, "sudo.log")) else ""
    check("G1 sudo: -n true at scan, then -v once", sudo.splitlines()[:2] == ["sudo -n true", "sudo -v"] and sudo.count("sudo -v") == 1, sudo)
    args = open(os.path.join(tmp, "args")).read().strip() if os.path.exists(os.path.join(tmp, "args")) else ""
    check("G1 install.sh got the Review command's flags (C5)",
          args == "--yes --profile personal --components shell,prompt --theme umbra --disable-k8s", args)
    state = os.path.join(tmp, "state", "um")
    logs = [f for f in os.listdir(state)] if os.path.isdir(state) else []
    log = next((open(os.path.join(state, f)).read() for f in logs if f.endswith(".log")), "")
    evs = next((open(os.path.join(state, f)).read() for f in logs if f.endswith(".events")), "")
    check("G1 the log has install.sh's output and the doctor's", "[fake] done" in log and "ok 04_prompt" in log, log)
    check("G1 the events file has both phases, prompt skipped",
          "\tphase\trun_onchange_before_20-shell.sh\tok\t" in evs and "\tphase\trun_onchange_before_30-prompt.sh\tskip\t" in evs, evs)
    check("G1 the run screen showed the phase and its log", "installing zsh" in text and "PHASES" in text, text[-2000:])
    shutil.rmtree(tmp, ignore_errors=True)


def g2_failed_phase():
    tmp = tempfile.mkdtemp(prefix="setup-pty-")
    steps = to_install() + [("password for tester", "test-password\r"), ("failed.", ENTER)]
    code, text, _ = driver.run([BIN], steps, run_env(tmp, FAKE_FAIL="1"), timeout=40)
    check("G2 a failing gate: the failed screen names it and the message, exit 1",
          code == 1 and "before_20-shell failed." in text and "zsh is missing" in text, text[-2500:])
    shutil.rmtree(tmp, ignore_errors=True)


def g3_stop_after_phase():
    tmp = tempfile.mkdtemp(prefix="setup-pty-")
    steps = to_install() + [("password for tester", "test-password\r"), ("installing zsh", CTRL_C), ("Stop after", "y"),
                            ("Nothing else ran.", ENTER)]
    code, text, _ = driver.run([BIN], steps, run_env(tmp, FAKE_SLEEP="2"), timeout=40)
    evs = ""
    state = os.path.join(tmp, "state", "um")
    if os.path.isdir(state):
        evs = "".join(open(os.path.join(state, f)).read() for f in os.listdir(state) if f.endswith(".events"))
    check("G3 ctrl+c, y: the running phase ends, nothing else starts, exit 130",
          code == 130 and "\tok\t" in evs and "before_30-prompt.sh\tstart" not in evs, text[-2500:] + "\n" + evs)
    shutil.rmtree(tmp, ignore_errors=True)


def g4_rerun_shows_installed():
    tmp = tempfile.mkdtemp(prefix="setup-pty-")
    os.makedirs(os.path.join(tmp, "config", "chezmoi"))
    with open(os.path.join(tmp, "config", "chezmoi", "chezmoi.toml"), "w") as f:
        f.write('sourceDir = "/x"\n\n[data]\n    profile = "work"\n    theme = "void"\n    components = "shell,prompt"\n')
    steps = [("enter continue", ENTER), ("Which profile", ENTER), ("of 10 selected", "q")]
    code, text, _ = driver.run([BIN], steps, run_env(tmp, UM_THEME=None), timeout=20)
    check("G4 a re-run opens with the stored selection, marked installed",
          code == 130 and "● work" in text and "2 of 10 selected" in text and "installed" in text, text[-2500:])
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    if not os.access(BIN, os.X_OK):
        sys.exit(f"build the binary first: go build -o build/umbra-setup ./cmd/umbra-setup ({BIN})")
    for f in (f1_defaults_dry_run, f2_work_untick_void, f3_cancel, f4_small, f5_no_tty, f6_no_color, f7_spanish, f8_ansi16,
              g1_run_with_sudo_and_doctor, g2_failed_phase, g3_stop_after_phase, g4_rerun_shows_installed):
        f()
    shutil.rmtree(ISOLATED, ignore_errors=True)
    ok = sum(results)
    print(f"setup-pty: {ok} ok, {len(results) - ok} failed")
    sys.exit(0 if ok == len(results) else 1)
