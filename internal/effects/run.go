package effects

import (
	"bufio"
	"context"
	"errors"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	tea "charm.land/bubbletea/v2"

	"github.com/Robertcl795/umbra-bootstrapper/internal/events"
	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
)

// ── scan (G4: the facts that need a process or the network) ──────────────────

// ScanSlow returns the scan facts that take time; each arrives as a ScanFact replacing the
// pending line with the same Key, plus Access and Sudo for the model.
func ScanSlow(e sys.Env) []tea.Cmd {
	return []tea.Cmd{systemd, network, sudoCheck(e), access(e)}
}

// Pending are the lines ScanSlow will fill, shown with a spinner until then.
func Pending() []msgs.ScanFact {
	return []msgs.ScanFact{
		{Key: "scan.systemd", State: msgs.FactPending},
		{Key: "scan.sudo", State: msgs.FactPending},
		{Key: "scan.network", State: msgs.FactPending},
		{Key: "scan.access", State: msgs.FactPending},
	}
}

func systemd() tea.Msg {
	comm, ok := readFile("/proc/1/comm")
	if ok && strings.TrimSpace(comm) == "systemd" {
		return msgs.ScanFact{Key: "scan.systemd", ValueKey: "scan.systemd.yes", State: msgs.FactOK}
	}
	return msgs.ScanFact{Key: "scan.systemd", Value: strings.TrimSpace(comm), ValueKey: "scan.systemd.no", State: msgs.FactNA}
}

func network() tea.Msg {
	start := time.Now()
	c, err := net.DialTimeout("tcp", "github.com:443", 5*time.Second)
	if err != nil {
		return msgs.ScanFact{Key: "scan.network", ValueKey: "scan.network.no", State: msgs.FactBad}
	}
	_ = c.Close()
	return msgs.ScanFact{Key: "scan.network", Value: time.Since(start).Round(time.Millisecond).String(), ValueKey: "scan.network.yes", State: msgs.FactOK}
}

func sudoCheck(e sys.Env) tea.Cmd {
	return func() tea.Msg {
		if e.Root {
			return msgs.Batch{msgs.ScanFact{Key: "scan.sudo", ValueKey: "scan.sudo.root", State: msgs.FactOK}, msgs.Sudo{Passwordless: true}}
		}
		if _, err := exec.LookPath("sudo"); err != nil {
			return msgs.Batch{msgs.ScanFact{Key: "scan.sudo", ValueKey: "scan.sudo.missing", State: msgs.FactBad}, msgs.Sudo{}}
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if exec.CommandContext(ctx, "sudo", "-n", "true").Run() == nil {
			return msgs.Batch{msgs.ScanFact{Key: "scan.sudo", ValueKey: "scan.sudo.free", State: msgs.FactOK}, msgs.Sudo{Passwordless: true}}
		}
		return msgs.Batch{msgs.ScanFact{Key: "scan.sudo", ValueKey: "scan.sudo.asks", State: msgs.FactOK}, msgs.Sudo{}}
	}
}

// access runs umbra_ai_access from selector.sh, the one rule for Umbra AI access (ADR 0018);
// UM_AI_ACCESS=0|1 still overrides it there.
func access(e sys.Env) tea.Cmd {
	return func() tea.Msg {
		script := `source "$UM_ENV_DIR/install/common.sh"; source "$UM_ENV_DIR/install/selector.sh"; umbra_ai_access`
		ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, "bash", "-c", script)
		cmd.Env = append(os.Environ(), "UM_ENV_DIR="+e.EnvDir)
		ok := cmd.Run() == nil
		f := msgs.ScanFact{Key: "scan.access", ValueKey: "scan.access.no", State: msgs.FactNA}
		if ok {
			f.ValueKey, f.State = "scan.access.yes", msgs.FactOK
		}
		return msgs.Batch{f, msgs.Access{OK: ok}}
	}
}

// Users reads the regular users from /etc/passwd (the account screen, as root).
func Users() tea.Msg {
	text, _ := readFile("/etc/passwd")
	return msgs.Users{Names: sys.RegularUsers(text)}
}

// ── stored selection (re-run) ────────────────────────────────────────────────

// Stored reads the [data] of chezmoi's config, where bootstrap.sh's selection is kept.
func Stored() tea.Msg {
	home, _ := os.UserHomeDir()
	dir := os.Getenv("XDG_CONFIG_HOME")
	if dir == "" {
		dir = filepath.Join(home, ".config")
	}
	text, ok := readFile(filepath.Join(dir, "chezmoi", "chezmoi.toml"))
	if !ok {
		return msgs.Stored{}
	}
	return sys.ParseStored(text)
}

// ── sudo ─────────────────────────────────────────────────────────────────────

// SudoValidate hands the terminal to `sudo -v` so it can ask for the password (ux-spec §3.1).
func SudoValidate() tea.Cmd {
	return tea.ExecProcess(exec.Command("sudo", "-v"), func(err error) tea.Msg {
		if err != nil {
			return msgs.SudoFailed{Err: err.Error()}
		}
		return msgs.SudoReady{}
	})
}

// SudoRefresh keeps the timestamp fresh every 60 s while the run lasts.
func SudoRefresh() tea.Cmd {
	return tea.Tick(60*time.Second, func(time.Time) tea.Msg {
		_ = exec.Command("sudo", "-n", "-v").Run()
		return msgs.SudoRefreshed{}
	})
}

// ── run ──────────────────────────────────────────────────────────────────────

// stateDir is $XDG_STATE_HOME/um (or ~/.local/state/um), where bootstrap.env also lives.
func stateDir() string {
	if d := os.Getenv("XDG_STATE_HOME"); d != "" {
		return filepath.Join(d, "um")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "state", "um")
}

// installer is the command a run executes: <root>/install.sh, or UM_SETUP_INSTALL (tests).
func installer(envDir string) string {
	if p := os.Getenv("UM_SETUP_INSTALL"); p != "" {
		return p
	}
	return filepath.Join(envDir, "..", "..", "install.sh")
}

// Start runs install.sh with args (the clock for the file names is read here, an effect). stdin is /dev/null, so nothing can wait for input behind the
// TUI; stdout and stderr go to the log; events go to a file next to it (ADR 0040); UM_STOP names
// the stop file. The child gets its own process group, so a terminal ctrl+c reaches only the TUI.
// A password (stage 1's new user, as root) goes in a 0600 file in a 0700 temp dir, named by
// UM_USER_PASSWORD_FILE (stage1.sh set_password) and removed when the child exits.
func Start(envDir string, args []string, password string) tea.Cmd {
	return func() tea.Msg {
		dir := stateDir()
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return msgs.RunErr{Err: err.Error()}
		}
		stamp := time.Now().UTC().Format("20060102T150405Z")
		logPath := filepath.Join(dir, "setup-"+stamp+".log")
		evPath := filepath.Join(dir, "setup-"+stamp+".events")
		stopPath := filepath.Join(dir, "setup-"+stamp+".stop")
		logf, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
		if err != nil {
			return msgs.RunErr{Err: err.Error()}
		}
		if err := os.WriteFile(evPath, nil, 0o644); err != nil {
			return msgs.RunErr{Err: err.Error()}
		}
		cmd := exec.Command("bash", append([]string{installer(envDir)}, args...)...)
		// GIT_TERMINAL_PROMPT=0: git asks on /dev/tty, not stdin; a prompt would draw over the TUI.
		// The access check already proved the credentials work without one.
		cmd.Env = append(os.Environ(), "UM_EVENTS="+evPath, "UM_STOP="+stopPath, "UM_ENV_DIR="+envDir, "GIT_TERMINAL_PROMPT=0")
		cmd.Stdout, cmd.Stderr = logf, logf
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		secret := ""
		if password != "" {
			d, err := os.MkdirTemp("", "umbra-setup-")
			if err != nil {
				_ = logf.Close()
				return msgs.RunErr{Err: err.Error()}
			}
			if err := os.WriteFile(filepath.Join(d, "password"), []byte(password+"\n"), 0o600); err != nil {
				_ = os.RemoveAll(d)
				_ = logf.Close()
				return msgs.RunErr{Err: err.Error()}
			}
			secret = d
			cmd.Env = append(cmd.Env, "UM_USER_PASSWORD_FILE="+filepath.Join(d, "password"))
		}
		if err := cmd.Start(); err != nil {
			_ = logf.Close()
			if secret != "" {
				_ = os.RemoveAll(secret)
			}
			return msgs.RunErr{Err: err.Error()}
		}
		mu.Lock()
		running[cmd.Process.Pid] = proc{cmd: cmd, log: logf, secret: secret}
		mu.Unlock()
		return msgs.RunStarted{PID: cmd.Process.Pid, Log: logPath, Events: evPath, Stop: stopPath}
	}
}

type proc struct {
	cmd    *exec.Cmd
	log    *os.File
	secret string // temp dir holding the password file, removed after Wait
}

// running holds the started children for Wait. It lives here, in the effects package, so the
// model stays pure (it only knows the pid). Commands run on their own goroutines: mu guards it.
var (
	mu      sync.Mutex
	running = map[int]proc{}
)

// Wait reports the child's exit code.
func Wait(pid int) tea.Cmd {
	return func() tea.Msg {
		mu.Lock()
		p, ok := running[pid]
		mu.Unlock()
		if !ok {
			return msgs.RunExited{Code: 1}
		}
		err := p.cmd.Wait()
		_ = p.log.Close()
		if p.secret != "" {
			_ = os.RemoveAll(p.secret)
		}
		mu.Lock()
		delete(running, pid)
		mu.Unlock()
		code := 0
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			code = ee.ExitCode()
		} else if err != nil {
			code = 1
		}
		return msgs.RunExited{Code: code}
	}
}

// ReadEvents reads the events added to path since offset, after a short pause (100 ms).
func ReadEvents(path string, offset int64) tea.Cmd {
	return tea.Tick(100*time.Millisecond, func(time.Time) tea.Msg {
		f, err := os.Open(path)
		if err != nil {
			return msgs.EventsRead{Offset: offset}
		}
		defer f.Close()
		if _, err := f.Seek(offset, io.SeekStart); err != nil {
			return msgs.EventsRead{Offset: offset}
		}
		var evs []events.Event
		r := bufio.NewReader(f)
		next := offset
		for {
			line, err := r.ReadString('\n')
			if err != nil { // a partial last line is read again next time
				break
			}
			next += int64(len(line))
			if ev, err := events.Parse(line); err == nil {
				evs = append(evs, ev)
			}
		}
		return msgs.EventsRead{Events: evs, Offset: next}
	})
}

// Stop creates the UM_STOP file: bash starts no phase after it exists, and the running phase
// finishes (common.sh phase_start). No signal is sent, so nothing is cut in the middle.
func Stop(path string) tea.Cmd {
	return func() tea.Msg {
		_ = os.WriteFile(path, nil, 0o644)
		return nil
	}
}

// Doctor runs tests/99_smoke.sh (or UM_SETUP_DOCTOR in tests) with the selection in env
// (plan.DoctorEnv), appending to the run's log.
func Doctor(envDir, logPath string, env []string) tea.Cmd {
	return func() tea.Msg {
		script := os.Getenv("UM_SETUP_DOCTOR")
		if script == "" {
			script = filepath.Join(envDir, "tests", "99_smoke.sh")
		}
		cmd := exec.Command("bash", script)
		home, _ := os.UserHomeDir()
		// As finish.sh does: tools installed by the run are on PATH for the doctor.
		cmd.Env = append(os.Environ(), "UM_ENV_DIR="+envDir, "UM_NO_FASTFETCH=1",
			"PATH="+filepath.Join(home, ".local", "bin")+":"+filepath.Join(home, ".cargo", "bin")+":"+os.Getenv("PATH"))
		cmd.Env = append(cmd.Env, env...)
		out, err := cmd.CombinedOutput()
		if f, ferr := os.OpenFile(logPath, os.O_APPEND|os.O_WRONLY, 0o644); ferr == nil {
			_, _ = f.Write(out)
			_ = f.Close()
		}
		return msgs.DoctorDone{OK: err == nil, Tail: tail(string(out), 8)}
	}
}

// LogTail reads the last n lines of the log.
func LogTail(path string, n int) tea.Cmd {
	return func() tea.Msg {
		text, _ := readFile(path)
		return msgs.LogTail{Lines: tail(text, n)}
	}
}

func tail(s string, n int) []string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return lines
}

// Tick drives spinners and times; the app asks for it only while something is pending.
func Tick() tea.Cmd {
	return tea.Tick(100*time.Millisecond, func(t time.Time) tea.Msg { return msgs.Tick{Now: t} })
}
