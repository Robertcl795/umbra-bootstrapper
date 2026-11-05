"""PTY driver for umbra-setup's tests. Copied from umbra-ai cli/test/pty/driver.py (the bootstrapper
stands alone, ADR 0014), with two changes: the child's terminal gets the size from COLUMNS/LINES,
so Bubble Tea reads a real window size; the screen follows CSI d (line position absolute), which
Bubble Tea v2 sends when rows move; and a step prompt "title:<text>" waits for that exact window
title. Bubble Tea writes only the cells that change, so on-screen text can arrive in pieces that
this small emulator does not always rebuild (seen in real WSL runs, 2026-11-05); a title is whole.

Original notes (um, PROMPT §5, with one change for Bubble Tea):

Bubble Tea redraws the screen, so a prompt string shows up many times. A step's prompt is
matched only in the output that arrived after the previous step's keys were sent. Everything
else is as verified in §5: ANSI is stripped before matching, every run has a timeout that kills
the child, and a killed run returns None (a failure, never a skip).
"""
import fcntl
import os
import pty
import struct
import termios
import re
import select
import signal
import time

ANSI = re.compile(rb"\x1b\[[0-9;?<>=]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[PX^_][^\x1b]*\x1b\\|\x1b[=>()][0-9A-Za-z]?|\r")


class Screen:
    """A minimal VT100 screen (stdlib only): enough of CSI cursor movement and erasing to follow
    Bubble Tea's incremental renderer, so prompts are matched on what the screen shows."""

    def __init__(self, cols=80, rows=30):
        self.W, self.H = cols, rows
        self.rows = [[" "] * cols for _ in range(rows)]
        self.r = self.c = 0
        self.saved = (0, 0)

    def _scroll(self):
        self.rows.pop(0)
        self.rows.append([" "] * self.W)

    def _lf(self):
        if self.r == self.H - 1:
            self._scroll()
        else:
            self.r += 1

    def feed(self, data: bytes):
        s = data.decode(errors="replace")
        i = 0
        while i < len(s):
            ch = s[i]
            if ch == "\x1b":
                m = re.match(r"\x1b\[([0-9;?<>=]*)([ -/]*)([@-~])", s[i:])
                if m:
                    self._csi(m.group(1), m.group(3))
                    i += m.end()
                    continue
                m = re.match(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", s[i:])
                if m:
                    i += m.end()
                    continue
                if s[i + 1:i + 2] == "7":
                    self.saved = (self.r, self.c)
                elif s[i + 1:i + 2] == "8":
                    self.r, self.c = self.saved
                i += 2
                continue
            if ch == "\r":
                self.c = 0
            elif ch == "\n":
                self._lf()
            elif ch == "\b":
                self.c = max(0, self.c - 1)
            elif ch == "\t":
                self.c = min(self.W - 1, (self.c // 8 + 1) * 8)
            elif ch >= " ":
                if self.c >= self.W:
                    self.c = 0
                    self._lf()
                self.rows[self.r][self.c] = ch
                self.c += 1
            i += 1

    def _csi(self, params, final):
        if params.startswith("?") or params.startswith(">") or params.startswith("<") or params.startswith("="):
            return
        ps = [int(p) if p else 0 for p in params.split(";")] if params else []
        n = (ps[0] if ps and ps[0] else 1)
        if final == "A":
            self.r = max(0, self.r - n)
        elif final == "B":
            self.r = min(self.H - 1, self.r + n)
        elif final == "C":
            self.c = min(self.W - 1, self.c + n)
        elif final == "D":
            self.c = max(0, self.c - n)
        elif final == "E":
            self.r, self.c = min(self.H - 1, self.r + n), 0
        elif final == "F":
            self.r, self.c = max(0, self.r - n), 0
        elif final == "G":
            self.c = min(self.W - 1, n - 1)
        elif final == "d":  # VPA, used by Bubble Tea v2's renderer (added for umbra-setup)
            self.r = min(self.H - 1, n - 1)
        elif final in "Hf":
            r = (ps[0] if ps and ps[0] else 1) - 1
            c = (ps[1] if len(ps) > 1 and ps[1] else 1) - 1
            self.r, self.c = min(self.H - 1, r), min(self.W - 1, c)
        elif final == "K":
            m = ps[0] if ps else 0
            row = self.rows[self.r]
            if m == 0:
                row[self.c:] = [" "] * (self.W - self.c)
            elif m == 1:
                row[:self.c + 1] = [" "] * (self.c + 1)
            else:
                self.rows[self.r] = [" "] * self.W
        elif final == "J":
            m = ps[0] if ps else 0
            if m == 0:
                self.rows[self.r][self.c:] = [" "] * (self.W - self.c)
                for k in range(self.r + 1, self.H):
                    self.rows[k] = [" "] * self.W
            elif m == 1:
                for k in range(0, self.r):
                    self.rows[k] = [" "] * self.W
            else:
                self.rows = [[" "] * self.W for _ in range(self.H)]
        elif final == "X":
            row = self.rows[self.r]
            row[self.c:self.c + n] = [" "] * len(row[self.c:self.c + n])
        elif final == "P":
            row = self.rows[self.r]
            del row[self.c:self.c + n]
            row.extend([" "] * (self.W - len(row)))
        elif final == "@":
            row = self.rows[self.r]
            row[self.c:self.c] = [" "] * n
            del row[self.W:]
        elif final == "L":
            for _ in range(n):
                self.rows.insert(self.r, [" "] * self.W)
                self.rows.pop()
        elif final == "M":
            for _ in range(n):
                self.rows.pop(self.r)
                self.rows.append([" "] * self.W)
        elif final == "S":
            for _ in range(n):
                self._scroll()
        elif final == "s":
            self.saved = (self.r, self.c)
        elif final == "u":
            self.r, self.c = self.saved

    def text(self):
        return "\n".join("".join(r).rstrip() for r in self.rows)


def clean(raw: bytes) -> str:
    return ANSI.sub(b"", raw).decode(errors="replace")


def run(argv, steps, env, timeout=10, settle=0.15, cwd=None):
    """steps: list of (prompt_substring, keys). A prompt matches in the output since the last keys or
    on the current screen once new output has arrived. Returns (exit_code | None, text, raw_bytes);
    text is the ANSI-stripped stream plus the final screen."""
    pid, fd = pty.fork()
    if pid == 0:
        rows, cols = int(env.get("LINES", "30")), int(env.get("COLUMNS", "80"))
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        if cwd:
            os.chdir(cwd)
        os.execvpe(argv[0], argv, env)
    raw, mark, i, end = b"", 0, 0, time.time() + timeout
    screen = Screen(int(env.get("COLUMNS", "80")), int(env.get("LINES", "30")))
    seen_at = None
    status = None
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                chunk = b""
            if not chunk:  # EIO/EOF: the child closed the terminal; collect its status
                while time.time() < end:
                    done, st = os.waitpid(pid, os.WNOHANG)
                    if done:
                        status = st
                        break
                    time.sleep(0.02)
                break
            raw += chunk
            screen.feed(chunk)
        if i < len(steps):
            fresh = len(raw) > mark or (i > 0 and steps[i - 1][1] == "")  # after an empty step, the screen is enough
            want = steps[i][0]
            if want.startswith("title:"):  # an OSC 0/2 window title, written whole on each change
                hit = bool(re.search(rb"\x1b\][02];" + re.escape(want[6:].encode()) + rb"(?:\x07|\x1b\\)", raw[mark:]))
            else:
                hit = want in clean(raw[mark:]) or want in screen.text()
            if seen_at is None and fresh and hit:
                seen_at = time.time()
            # let the frame finish drawing before typing
            if seen_at is not None and time.time() - seen_at >= settle:
                mark = len(raw)
                os.write(fd, steps[i][1].encode())
                i, seen_at = i + 1, None
        done, st = os.waitpid(pid, os.WNOHANG)
        if done:
            status = st
            # drain what is left
            while True:
                r, _, _ = select.select([fd], [], [], 0.1)
                if not r:
                    break
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                raw += chunk
                screen.feed(chunk)
            break
    text = clean(raw) + "\n--- screen ---\n" + screen.text()
    if status is None:
        try:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        except ProcessLookupError:
            pass
        return None, text, raw
    return os.waitstatus_to_exitcode(status), text, raw
