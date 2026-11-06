package app

import (
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"

	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
)

type defaultCalls struct {
	status, apply, sudo int
	shell               string
	wt                  bool
}

func defaultCmds(c *calls, d *defaultCalls) Cmds {
	cmds := fakeCmds(c)
	none := func() tea.Msg { return nil }
	cmds.DefaultStatus = func() tea.Cmd { d.status++; return none }
	cmds.MakeDefault = func(shell string, wt bool) tea.Cmd { d.apply++; d.shell, d.wt = shell, wt; return none }
	cmds.SudoValidate = func() tea.Cmd { d.sudo++; return none }
	return cmds
}

// toDone runs a selection (keys on the Shell screen) to a passed doctor.
func toDone(t *testing.T, env sys.Env, d *defaultCalls, shellKeys ...string) Model {
	t.Helper()
	m := started(t, env, 80, 24, defaultCmds(&calls{}, d))
	m, _ = press(m, "enter", "enter", "enter")
	m, _ = press(m, shellKeys...)
	m, _ = press(m, "enter", "enter")
	m.d.Passwordless = true
	m, _ = press(m, "enter")
	if m.screen != Run {
		t.Fatalf("screen %d, want Run", m.screen)
	}
	return send(m, msgs.RunStarted{PID: 1, Log: "/tmp/l", Events: "/tmp/e"}, msgs.RunExited{Code: 0}, msgs.EventsRead{},
		msgs.DoctorDone{OK: true})
}

// After a passed run, Make default asks before the login shell changes (plan T4, R5).
func TestMakeDefaultAsksThenSetsTheLoginShell(t *testing.T) {
	d := &defaultCalls{}
	m := toDone(t, fixtureEnv("umbra", theme.None, "en"), d, "down", "space") // fish
	if m.screen != MakeDefault || d.status != 1 {
		t.Fatalf("screen %d, status calls %d", m.screen, d.status)
	}
	m = send(m, msgs.DefaultStatus{Login: "/bin/bash"})
	if !strings.HasPrefix(m.Title(), "Umbra setup · default") || !strings.Contains(m.Content(), "now bash") {
		t.Fatalf("title %q\n%s", m.Title(), m.Content())
	}
	m, _ = press(m, "enter")
	// usermod needs sudo: its timestamp is renewed first (finish.sh removed stage 2's rule).
	if d.sudo != 1 || d.apply != 0 {
		t.Fatalf("enter: sudo %d apply %d, want sudo first", d.sudo, d.apply)
	}
	m = send(m, msgs.SudoReady{})
	if d.apply != 1 || d.shell != "fish" || d.wt {
		t.Fatalf("apply %+v", d)
	}
	m = send(m, msgs.DefaultDone{Lines: []string{"Your login shell is now fish (/usr/bin/fish)"}})
	if m.screen != Done || !strings.Contains(m.Content(), "Your login shell is now fish") {
		t.Fatalf("screen %d\n%s", m.screen, m.Content())
	}
}

func TestKeepCurrentChangesNothing(t *testing.T) {
	d := &defaultCalls{}
	m := send(toDone(t, fixtureEnv("umbra", theme.None, "en"), d, "down", "space"), msgs.DefaultStatus{Login: "/bin/bash"})
	m, _ = press(m, "esc")
	if m.screen != Done || d.apply != 0 {
		t.Fatalf("screen %d apply %d", m.screen, d.apply)
	}
}

// Already the default: no question.
func TestMakeDefaultIsSkippedWhenNothingChanges(t *testing.T) {
	d := &defaultCalls{}
	m := send(toDone(t, fixtureEnv("umbra", theme.None, "en"), d), msgs.DefaultStatus{Login: "/usr/bin/zsh"})
	if m.screen != Done || d.apply != 0 {
		t.Fatalf("screen %d apply %d", m.screen, d.apply)
	}
	// No shell setup and no PowerShell 7: nothing to ask, not even the status.
	e := &defaultCalls{}
	n := toDone(t, fixtureEnv("umbra", theme.None, "en"), e, "down", "down", "space")
	if n.screen != Done || e.status != 0 {
		t.Fatalf("no shell: screen %d status %d", n.screen, e.status)
	}
}

// PowerShell 7: Windows Terminal's default profile, also only after the user confirms (Q3);
// without the profile in Windows Terminal yet, the row says what to do and is not applied.
func TestMakeDefaultPowerShell7(t *testing.T) {
	d := &defaultCalls{}
	m := toDone(t, fixtureEnv("umbra", theme.None, "en"), d, "down", "down", "down", "space")
	m = send(m, msgs.DefaultStatus{Login: "/usr/bin/zsh", WTDefault: "{a}", WTPwsh7: "{b}"})
	if m.screen != MakeDefault || !strings.Contains(m.Content(), "PowerShell 7") {
		t.Fatalf("screen %d\n%s", m.screen, m.Content())
	}
	m, _ = press(m, "enter")
	if d.sudo != 0 || d.apply != 1 || d.shell != "" || !d.wt {
		t.Fatalf("Windows Terminal only needs no sudo: %+v", d)
	}
	e := &defaultCalls{}
	n := toDone(t, fixtureEnv("umbra", theme.None, "en"), e, "down", "down", "down", "space")
	n = send(n, msgs.DefaultStatus{Login: "/bin/bash", WTDefault: "{a}"})
	if !strings.Contains(n.Content(), "does not list PowerShell 7 yet") {
		t.Errorf("no hint:\n%s", n.Content())
	}
	n, _ = press(n, "enter")
	n = send(n, msgs.SudoReady{})
	if e.shell != "zsh" || e.wt {
		t.Errorf("apply %+v", e)
	}
}

// A row can be unticked: only the ticked ones change.
func TestUntickedRowsAreNotApplied(t *testing.T) {
	d := &defaultCalls{}
	m := toDone(t, fixtureEnv("umbra", theme.None, "en"), d, "down", "space", "down", "down", "space")
	m = send(m, msgs.DefaultStatus{Login: "/bin/bash", WTDefault: "{a}", WTPwsh7: "{b}"})
	m, _ = press(m, "space", "enter") // untick the login shell
	if d.shell != "" || !d.wt {
		t.Fatalf("apply %+v", d)
	}
}

// A failed sudo says why on Done and changes nothing.
func TestMakeDefaultWhenSudoFails(t *testing.T) {
	d := &defaultCalls{}
	m := send(toDone(t, fixtureEnv("umbra", theme.None, "en"), d, "down", "space"), msgs.DefaultStatus{Login: "/bin/bash"})
	m, _ = press(m, "enter")
	m = send(m, msgs.SudoFailed{Err: "exit status 1"})
	if m.screen != Done || d.apply != 0 || !strings.Contains(m.Content(), "exit status 1") {
		t.Fatalf("screen %d apply %d\n%s", m.screen, d.apply, m.Content())
	}
}

// Omarchy keeps its login shell (ADR 0011): no Make default.
func TestOmarchyHasNoMakeDefault(t *testing.T) {
	d := &defaultCalls{}
	e := fixtureEnv("umbra", theme.None, "en")
	e.Platform = "omarchy"
	m := toDone(t, e, d)
	if m.screen != Done || d.status != 0 {
		t.Fatalf("screen %d status %d", m.screen, d.status)
	}
}

func TestMakeDefaultGolden(t *testing.T) {
	for pn, p := range profiles {
		d := &defaultCalls{}
		m := toDone(t, fixtureEnv("umbra", p, "en"), d, "down", "space", "down", "down", "space")
		m = send(m, msgs.DefaultStatus{Login: "/bin/bash", WTDefault: "{a}", WTPwsh7: "{b}"})
		checkGolden(t, "default_umbra_"+pn, m.Content())
	}
	d := &defaultCalls{}
	m := toDone(t, fixtureEnv("umbra", theme.None, "es"), d, "down", "space", "down", "down", "space")
	m = send(m, msgs.DefaultStatus{Login: "/bin/bash", WTDefault: "{a}"})
	checkGolden(t, "es_default", m.Content())
}
