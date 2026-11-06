package app

import (
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/ansi"

	"github.com/Robertcl795/umbra-bootstrapper/internal/events"
	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/plan"
	"github.com/Robertcl795/umbra-bootstrapper/internal/screens"
	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
)

// atAccount is root on WSL, on the account screen.
func atAccount(t *testing.T, env sys.Env) Model {
	t.Helper()
	env.Root, env.Distro = true, "Arch"
	m := send(started(t, env, 80, 24, fakeCmds(&calls{})), msgs.Users{})
	m, _ = press(m, "enter", "enter")
	if m.screen != Account {
		t.Fatalf("screen %d, want Account", m.screen)
	}
	return m
}

// left is what the screen shows on the cursor's row, left of the cursor.
func left(t *testing.T, m Model, cur *tea.Cursor) string {
	t.Helper()
	rows := strings.Split(ansi.Strip(m.Content()), "\n")
	if cur.Y < 0 || cur.Y >= len(rows) {
		t.Fatalf("cursor row %d outside the screen", cur.Y)
	}
	return strings.TrimRight(ansi.Cut(rows[cur.Y], 0, cur.X), " ")
}

// The field's cursor is the terminal's own bar cursor, right after the text: the terminal blinks
// it while nobody types (ux fix 2026-11-05: a static bar sat at the field's right end).
func TestAccountCursorIsTheTerminalCursorAfterTheText(t *testing.T) {
	m := atAccount(t, motionEnv())
	if strings.Contains(m.Content(), "▏") {
		t.Fatal("the field still draws its own bar")
	}
	cur := m.View().Cursor
	if cur == nil || cur.Shape != tea.CursorBar || !cur.Blink {
		t.Fatalf("cursor %+v, want a blinking bar", cur)
	}
	if got := left(t, m, cur); !strings.HasSuffix(got, "username") {
		t.Fatalf("empty user field: left of the cursor is %q", got)
	}
	m = typeText(m, "umb")
	cur = m.View().Cursor
	if got := left(t, m, cur); !strings.HasSuffix(got, "username          umb") {
		t.Fatalf("after typing: left of the cursor is %q", got)
	}
	m, _ = press(m, "tab")
	m = typeText(m, "pw")
	cur = m.View().Cursor
	if got := left(t, m, cur); !strings.HasSuffix(got, "••") || !strings.Contains(got, "password") {
		t.Fatalf("password field: left of the cursor is %q", got)
	}
	n := atAccount(t, fixtureEnv("umbra", theme.TrueColor, "en"))
	if cur := n.View().Cursor; cur == nil || cur.Blink {
		t.Fatalf("NO_MOTION: cursor %+v, want a steady bar", cur)
	}
	n, _ = press(n, "enter", "enter", "enter")
	if n.screen != Account || n.View().Cursor == nil {
		t.Fatal("the cursor must stay on the account screen")
	}
	o := started(t, fixtureEnv("umbra", theme.TrueColor, "en"), 80, 24)
	if o.View().Cursor != nil {
		t.Fatal("screens without a text field show no cursor")
	}
}

// Stage 1 (root on WSL) lists its own phases, in its order; no chezmoi script runs there.
func TestStage1ListsItsPhasesInOrder(t *testing.T) {
	m := atAccount(t, fixtureEnv("umbra", theme.TrueColor, "en"))
	m = typeText(m, "umbra")
	m, _ = press(m, "tab")
	m = typeText(m, "pw")
	m, _ = press(m, "tab")
	m = typeText(m, "pw")
	m, _ = press(m, "enter", "enter", "enter", "enter", "enter")
	if m.screen != Run {
		t.Fatalf("screen %d, want Run", m.screen)
	}
	if got := phaseIDs(m); !slices.Equal(got, plan.Stage1) {
		t.Fatalf("stage 1 phases %v, want %v", got, plan.Stage1)
	}
}

// plan.Stage1 is the list stage1.sh runs (contract with run_stage1).
func TestStage1PhasesMatchStage1Sh(t *testing.T) {
	b, err := os.ReadFile(envDir() + "/install/stage1.sh")
	if err != nil {
		t.Fatal(err)
	}
	var ids []string
	for _, m := range regexp.MustCompile(`(?m)^\s+phase (P\w+) `).FindAllStringSubmatch(string(b), -1) {
		ids = append(ids, m[1])
	}
	if !slices.Equal(ids, plan.Stage1) {
		t.Fatalf("stage1.sh runs %v, plan.Stage1 is %v", ids, plan.Stage1)
	}
}

// A phase the list did not have goes right after the last phase that started, not at the end.
func TestAnUnlistedPhaseGoesWhereItRan(t *testing.T) {
	m := toRun(t, &calls{}, true)
	ids := phaseIDs(m)
	m = send(m, msgs.EventsRead{Events: []events.Event{
		ev(0, "phase", ids[0], "start", ""), ev(1, "phase", ids[0], "ok", ""),
		ev(1, "phase", "retire-links", "start", ""),
	}, Offset: 5})
	got := phaseIDs(m)
	if got[1] != "retire-links" || got[len(got)-1] != plan.Doctor {
		t.Fatalf("phases %v: retire-links must follow %s", got, ids[0])
	}
}

// On WSL, enter on the restart screen leaves the distro (umbra-setup then terminates it, so the
// user is back in PowerShell); q only closes umbra-setup.
func TestRestartEnterLeavesWSL(t *testing.T) {
	m := atRestart(t)
	if !strings.Contains(m.Content(), "leave WSL") {
		t.Fatalf("the footer does not name leaving WSL:\n%s", m.Content())
	}
	e, _ := press(m, "enter")
	if r := e.Result(); r.Action != screens.Leave || r.Code != 0 {
		t.Fatalf("enter: %+v", r)
	}
	q, _ := press(m, "q")
	if r := q.Result(); r.Action != screens.Next {
		t.Fatalf("q: %+v", r)
	}
}

func atRestart(t *testing.T) Model {
	t.Helper()
	return atRestartIn(t, fixtureEnv("umbra", theme.TrueColor, "en"))
}

func atRestartIn(t *testing.T, e sys.Env) Model {
	t.Helper()
	m := atAccount(t, e)
	m = typeText(m, "umbra")
	m, _ = press(m, "tab")
	m = typeText(m, "pw")
	m, _ = press(m, "tab")
	m = typeText(m, "pw")
	m, _ = press(m, "enter", "enter", "enter", "enter")
	m = send(m, msgs.RunStarted{PID: 1, Log: "/tmp/l", Events: "/tmp/e"},
		msgs.EventsRead{Events: []events.Event{ev(0, "phase", "P0", "start", ""), ev(1, "phase", "P0", "ok", "")}},
		msgs.RunExited{Code: 0}, msgs.EventsRead{})
	if m.screen != Restart {
		t.Fatalf("screen %d, want Restart", m.screen)
	}
	return m
}

// In truecolor every cell carries the variant's background, also after each reset: a terminal
// that ignores OSC 11 (or has a light scheme) never shows its own background through void.
func TestTruecolorPaintsTheBackgroundInEveryCell(t *testing.T) {
	m := started(t, fixtureEnv("void", theme.TrueColor, "en"), 80, 24)
	bg := "\x1b[48;2;" // void's bg, as SGR
	out := m.View().Content
	for i, line := range strings.Split(out, "\n") {
		if !strings.HasPrefix(line, bg) {
			t.Fatalf("line %d does not start on the background: %q", i, line[:min(len(line), 30)])
		}
	}
	for _, reset := range regexp.MustCompile(`\x1b\[0?m`).FindAllStringIndex(out, -1) {
		rest := out[reset[1]:]
		if rest != "" && !strings.HasPrefix(rest, bg) && !strings.HasPrefix(rest, "\n") {
			t.Fatalf("a reset leaves the terminal's background: %q", rest[:min(len(rest), 30)])
		}
	}
	if ansi.Strip(out) != ansi.Strip(m.Content()) {
		t.Fatal("painting changed the text")
	}
	n := started(t, fixtureEnv("void", theme.ANSI16, "en"), 80, 24)
	if strings.Contains(n.View().Content, "\x1b[48;2;") {
		t.Fatal("ANSI-16 keeps the terminal's background")
	}
}

// ADR 0042: under install.ps1 (UM_DRIVER=ps1) the restart screen hands the restart to the
// driver. Enter exits with code 10 and terminates nothing; q exits 0 (the driver stops there).
func TestRestartUnderThePowerShellDriverExitsTen(t *testing.T) {
	e := fixtureEnv("umbra", theme.TrueColor, "en")
	e.Driver = "ps1"
	m := atRestartIn(t, e)
	if !strings.Contains(m.Content(), "continue in PowerShell") {
		t.Fatalf("the footer does not name PowerShell:\n%s", m.Content())
	}
	en, _ := press(m, "enter")
	if r := en.Result(); r.Action != screens.Next || r.Code != 10 {
		t.Fatalf("enter: %+v, want Next with code 10 (no Leave: the driver terminates)", r)
	}
	q, _ := press(m, "q")
	if r := q.Result(); r.Action != screens.Next || r.Code != 0 {
		t.Fatalf("q: %+v, want Next with code 0", r)
	}
}
