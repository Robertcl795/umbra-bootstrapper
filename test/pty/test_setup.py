"""PTY tests of umbra-setup (setup-tui ux-spec §8, gate G3): the real binary in a real terminal.

Usage (from the bootstrapper root):  go build -o build/umbra-setup ./cmd/umbra-setup
                                      python3 -I test/pty/test_setup.py
Prints one line per check and "setup-pty: N ok, M failed"; exits 1 on any failure.
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import driver  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BIN = os.path.join(ROOT, "build", "umbra-setup")
ENV_DIR = os.path.join(ROOT, "env", "wsl")
ENTER, DOWN, RIGHT, SPACE, CTRL_C = "\r", "\x1b[B", "\x1b[C", " ", "\x03"

results = []


def check(name, cond, detail=""):
    results.append(bool(cond))
    print(("  ok   " if cond else "  FAIL ") + name)
    if not cond and detail:
        print("       " + detail.replace("\n", "\n       ")[-1500:])


def env(**extra):
    e = {
        "PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp"), "TERM": "xterm-256color",
        "COLUMNS": "80", "LINES": "24", "LANG": "C.UTF-8", "UM_LANG": "en", "UM_THEME": "umbra",
        "COLORTERM": "truecolor", "UM_OS": "arch", "UM_IS_WSL": "1", "UM_AI_ACCESS": "1",
        "UM_REDUCED_MOTION": "1", "UM_ENV_DIR": ENV_DIR,
    }
    e.update(extra)
    return {k: v for k, v in e.items() if v is not None}


def walk_to_review():
    return [("SYSTEM SCAN", ENTER), ("Which profile", ENTER), ("of 10 selected", ENTER),
            ("Pick a variant", ENTER), ("[ Install ]", "")]


def printed_command(text):
    m = re.search(r"^\s*(install\.sh .*)$", text, re.M)
    return m.group(1) if m else ""


def dry_run(cmd):
    """Run the printed install.sh line with --dry-run; return its last line."""
    args = cmd.split()[1:]
    out = subprocess.run(["bash", os.path.join(ROOT, "install.sh"), "--dry-run", *args],
                         env={"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp"),
                              "UM_OS": "arch", "UM_IS_WSL": "1", "UM_AI_ACCESS": "1"},
                         capture_output=True, text=True, timeout=20, stdin=subprocess.DEVNULL)
    return out.stdout.strip().splitlines()[-1] if out.stdout.strip() else out.stderr


def f1_defaults_install():
    steps = walk_to_review()[:-1] + [("[ Install ]", ENTER)]
    code, text, raw = driver.run([BIN], steps, env())
    cmd = printed_command(text)
    check("F1 defaults: Install exits 0 and prints the install.sh command", code == 0 and cmd, text)
    check("F1 the command names every default component",
          "--components packages,shell,prompt,nvim,k8s,zellij,lang,fastfetch,wsl,ai-cli,ai-standard,um,vault,ollama " in cmd, cmd)
    line = dry_run(cmd)
    check("F1 install.sh --dry-run with that command plans the same (contract C5)",
          "platform=wsl-arch profile=personal components=packages,shell,prompt,nvim,k8s,zellij,lang,fastfetch,wsl,ai-cli,ai-standard,um,vault,ollama" in line, line)
    check("F1 nothing installed is said", "Nothing was installed" in text, text)
    check("F1 truecolor paints the variant background (OSC 11)", b"\x1b]11;" in raw)
    check("F1 the background is reset on exit (OSC 111)", b"\x1b]111" in raw)


def f2_work_untick_void():
    steps = [("SYSTEM SCAN", ENTER), ("Which profile", DOWN), ("Check your company", ENTER),
             ("of 10 selected", SPACE), ("9 of 10 selected", ENTER),
             ("Pick a variant", RIGHT), ("UM_THEME=void", ENTER), ("[ Install ]", ENTER)]
    code, text, _ = driver.run([BIN], steps, env())
    cmd = printed_command(text)
    check("F2 work, packages unticked, void: exit 0", code == 0, text)
    check("F2 the command carries the picks",
          cmd.startswith("install.sh --yes --profile work --components shell,") and "--theme void" in cmd and "packages" not in cmd, cmd)
    line = dry_run(cmd)
    check("F2 install.sh --dry-run agrees", "profile=work components=shell,prompt" in line, line)


def f3_cancel():
    code, text, _ = driver.run([BIN], [("SYSTEM SCAN", ENTER), ("Which profile", CTRL_C)], env())
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
    code, text, _ = driver.run([BIN], [("ESCANEO DEL SISTEMA", ENTER), ("¿Qué perfil", "q")], env(UM_LANG="es"))
    check("F7 UM_LANG=es: the screens are in Spanish", code == 130 and "Cancelado. No se instaló nada." in text, text)


def f8_ansi16():
    code, text, raw = driver.run([BIN], [("SYSTEM SCAN", "q")], env(COLORTERM=None))
    check("F8 no COLORTERM: ANSI-16 slots (SGR 30-37), no truecolor", code == 130 and b"38;2;" not in raw and re.search(rb"\x1b\[[0-9;]*3[0-7]m", raw), text)


if __name__ == "__main__":
    if not os.access(BIN, os.X_OK):
        sys.exit(f"build the binary first: go build -o build/umbra-setup ./cmd/umbra-setup ({BIN})")
    for f in (f1_defaults_install, f2_work_untick_void, f3_cancel, f4_small, f5_no_tty, f6_no_color, f7_spanish, f8_ansi16):
        f()
    ok = sum(results)
    print(f"setup-pty: {ok} ok, {len(results) - ok} failed")
    sys.exit(0 if ok == len(results) else 1)
