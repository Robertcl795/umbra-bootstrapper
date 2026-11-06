package app

import (
	"slices"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"

	"github.com/Robertcl795/umbra-bootstrapper/internal/events"
	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/plan"
	"github.com/Robertcl795/umbra-bootstrapper/internal/screens"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
)

// calls records which effects the app asked for.
type calls struct {
	start, sudo, doctor, tail, stop int
	stopFile                        string
	doctorEnv                       []string
	password                        string
}

func fakeCmds(c *calls) Cmds {
	none := func() tea.Msg { return nil }
	return Cmds{
		Start:        func(_ []string, pw string) tea.Cmd { c.start++; c.password = pw; return none },
		SudoValidate: func() tea.Cmd { c.sudo++; return none },
		Doctor:       func(_ string, env []string) tea.Cmd { c.doctor++; c.doctorEnv = env; return none },
		LogTail:      func(string) tea.Cmd { c.tail++; return none },
		Stop:         func(f string) tea.Cmd { c.stop++; c.stopFile = f; return none },
		Wait:         func(int) tea.Cmd { return none },
		ReadEvents:   func(string, int64) tea.Cmd { return none },
	}
}

var t0 = time.Date(2026, 11, 5, 10, 0, 0, 0, time.UTC)

func ev(sec int, kind, phase, state, msg string) events.Event {
	return events.Event{At: t0.Add(time.Duration(sec) * time.Second), Kind: kind, Phase: phase, State: state, Message: msg}
}

func send(m Model, ms ...tea.Msg) Model {
	var tm tea.Model = m
	for _, msg := range ms {
		tm, _ = tm.Update(msg)
	}
	return tm.(Model)
}

// toRun goes to review with only shell and prompt, then presses Install.
func toRun(t *testing.T, c *calls, passwordless bool) Model {
	t.Helper()
	m := started(t, fixtureEnv("umbra", theme.TrueColor, "en"), 80, 24, fakeCmds(c))
	m, _ = press(m, "enter", "enter", "n", "down", "space", "down", "space", "enter", "enter")
	m.d.Passwordless = passwordless
	m, _ = press(m, "enter")
	return m
}

const (
	shell  = "run_onchange_before_20-shell.sh"
	prompt = "run_onchange_before_30-prompt.sh"
)

func TestRunSucceedsThroughTheDoctor(t *testing.T) {
	c := &calls{}
	m := toRun(t, c, true)
	if m.screen != Run || c.start != 1 || c.sudo != 0 {
		t.Fatalf("screen %d start %d sudo %d", m.screen, c.start, c.sudo)
	}
	m = send(m, msgs.RunStarted{PID: 42, Log: "/tmp/setup.log", Events: "/tmp/setup.events"},
		msgs.EventsRead{Events: []events.Event{
			ev(0, "phase", shell, "start", ""), ev(1, "log", shell, "info", "installing zsh"), ev(3, "phase", shell, "ok", "gate shell"),
			ev(3, "phase", prompt, "start", ""), ev(4, "phase", prompt, "skip", ""),
			ev(4, "phase", "P9-extra", "start", ""), ev(5, "phase", "P9-extra", "ok", ""),
		}, Offset: 100})
	if !strings.Contains(m.Content(), "installing zsh") && m.r.Current != "P9-extra" {
		t.Error("log of the current phase")
	}
	if ids := phaseIDs(m); ids[2] != "P9-extra" || ids[len(ids)-1] != plan.Doctor {
		t.Errorf("an unknown phase goes where it ran (after prompt), the doctor last: %v", ids)
	}
	m = send(m, msgs.RunExited{Code: 0}, msgs.EventsRead{Offset: 100})
	if c.doctor != 1 || m.r.Current != plan.Doctor {
		t.Fatalf("doctor not started: %d %q", c.doctor, m.r.Current)
	}
	if want := []string{"UM_COMPONENTS=shell,prompt", "UM_SKIP=", "UM_SKIP_PACKAGES=", "UM_MODE=personal"}; !slices.Equal(c.doctorEnv, want) {
		t.Errorf("doctor env %v, want %v (only what was selected)", c.doctorEnv, want)
	}
	m = send(m, msgs.DoctorDone{OK: true, Tail: []string{"all good"}})
	if m.screen != Done {
		t.Fatalf("screen %d, want Done", m.screen)
	}
	states := map[string]screens.PhaseState{}
	for _, p := range m.r.Phases {
		states[p.ID] = p.State
	}
	if states[shell] != screens.Passed || states[prompt] != screens.Skipped || states[plan.Summary] != screens.Unchanged || states[plan.Doctor] != screens.Passed {
		t.Errorf("states %v", states)
	}
	if !strings.Contains(m.Content(), "Umbra is set up.") {
		t.Error("done text")
	}
	m, _ = press(m, "enter")
	if m.Result().Code != 0 {
		t.Errorf("code %d", m.Result().Code)
	}
}

func TestRunFailureShowsThePhaseAndItsMessage(t *testing.T) {
	c := &calls{}
	m := toRun(t, c, true)
	m = send(m, msgs.RunStarted{PID: 7, Log: "/tmp/l", Events: "/tmp/e"},
		msgs.EventsRead{Events: []events.Event{ev(0, "phase", shell, "start", ""), ev(2, "phase", shell, "fail", "zsh is missing")}},
		msgs.RunExited{Code: 1}, msgs.EventsRead{}, msgs.LogTail{Lines: []string{"[ERROR] gate shell failed: zsh is missing"}})
	if m.screen != Failed || c.doctor != 0 || c.tail != 1 {
		t.Fatalf("screen %d doctor %d tail %d", m.screen, c.doctor, c.tail)
	}
	got := m.Content()
	for _, want := range []string{"before_20-shell failed.", "zsh is missing", "gate shell failed", "install.sh --yes"} {
		if !strings.Contains(got, want) {
			t.Errorf("failed screen lacks %q", want)
		}
	}
	m, _ = press(m, "enter")
	if m.Result().Code != 1 {
		t.Errorf("code %d", m.Result().Code)
	}
}

// Stop asks bash, through the stop file, to start nothing after the running phase (ux-spec §3.1).
func TestStopCreatesTheStopFileAndWaits(t *testing.T) {
	c := &calls{}
	m := toRun(t, c, true)
	m = send(m, msgs.RunStarted{PID: 99, Log: "/tmp/l", Events: "/tmp/e", Stop: "/tmp/setup.stop"},
		msgs.EventsRead{Events: []events.Event{ev(0, "phase", shell, "start", "")}})
	m, _ = press(m, "ctrl+c")
	if !m.r.StopAsk || m.screen != Run || c.stop != 0 {
		t.Fatal("ctrl+c does not only ask")
	}
	if !strings.Contains(m.Content(), "Stop after before_20-shell?") {
		t.Error("question text")
	}
	m, _ = press(m, "n")
	if m.r.StopAsk || c.stop != 0 {
		t.Fatal("n does not cancel the question")
	}
	m, _ = press(m, "ctrl+c", "y")
	if c.stop != 1 || c.stopFile != "/tmp/setup.stop" || m.screen != Run {
		t.Fatalf("stop %d file %q screen %d", c.stop, c.stopFile, m.screen)
	}
	if !strings.Contains(m.Content(), "Stopping after before_20-shell.") {
		t.Error("stopping text")
	}
	m = send(m, msgs.EventsRead{Events: []events.Event{ev(3, "phase", shell, "ok", "")}}, msgs.RunExited{Code: 1}, msgs.EventsRead{})
	if m.screen != Failed || !strings.Contains(m.Content(), "Stopped after before_20-shell. Nothing else ran.") {
		t.Fatalf("screen %d", m.screen)
	}
	m, _ = press(m, "enter")
	if m.Result().Code != 130 {
		t.Errorf("code %d", m.Result().Code)
	}
}

func TestSudoAsksOnceBeforeTheRun(t *testing.T) {
	c := &calls{}
	m := toRun(t, c, false)
	if c.sudo != 1 || c.start != 0 || m.screen != Review {
		t.Fatalf("sudo %d start %d screen %d", c.sudo, c.start, m.screen)
	}
	m = send(m, msgs.SudoFailed{Err: "exit status 1"})
	if m.screen != Review || !strings.Contains(m.Content(), "sudo did not get a password: exit status 1") {
		t.Fatal("sudo failure not on review")
	}
	m, _ = press(m, "enter")
	m = send(m, msgs.SudoReady{})
	if c.start != 1 || m.screen != Run {
		t.Fatalf("start %d screen %d", c.start, m.screen)
	}
}

func typeText(m Model, text string) Model {
	for _, r := range text {
		var tm tea.Model = m
		tm, _ = tm.Update(tea.KeyPressMsg{Code: r, Text: string(r)})
		m = tm.(Model)
	}
	return m
}

// As root on WSL, stage 1 is told the user and gets the password in a file (stage1.sh p2_pre).
func TestRootAsksForTheAccountAndEndsAtTheRestartPoint(t *testing.T) {
	c := &calls{}
	env := fixtureEnv("umbra", theme.TrueColor, "en")
	env.Root, env.Distro = true, "Arch"
	m := started(t, env, 80, 24, fakeCmds(c))
	m = send(m, msgs.Users{})
	m, _ = press(m, "enter", "enter")
	if m.screen != Account {
		t.Fatalf("screen %d, want Account", m.screen)
	}
	m = typeText(m, "Bad User")
	m, _ = press(m, "enter", "enter", "enter")
	if m.acct.Err != "account.bad.user" || m.screen != Account {
		t.Fatalf("invalid name accepted: %+v", m.acct)
	}
	m.acct.User = ""
	m = typeText(m, "umbra")
	m, _ = press(m, "tab")
	m = typeText(m, "s3cret pw")
	m, _ = press(m, "tab")
	m = typeText(m, "s3cret px")
	m, _ = press(m, "enter")
	if m.acct.Err != "account.bad.match" || m.acct.Again != "" {
		t.Fatalf("mismatch accepted: %+v", m.acct)
	}
	if got := m.Content(); strings.Contains(got, "s3cret") || !strings.Contains(got, "•••••••••") {
		t.Fatal("the password is drawn, or not masked")
	}
	m = typeText(m, "s3cret pw")
	m, _ = press(m, "enter")
	if m.screen != Components {
		t.Fatalf("screen %d, want Components", m.screen)
	}
	m, _ = press(m, "enter", "enter")
	if args := strings.Join(m.d.Args(), " "); !strings.HasSuffix(args, "--user umbra") {
		t.Errorf("install.sh args lack --user: %s", args)
	}
	if review := m.Content(); !strings.Contains(review, "--user") || strings.Contains(review, "s3cret") {
		t.Errorf("review must show --user and never the password:\n%s", review)
	}
	m, _ = press(m, "enter")
	if c.sudo != 0 || c.start != 1 || c.password != "s3cret pw" {
		t.Fatalf("root: sudo %d start %d password %q", c.sudo, c.start, c.password)
	}
	m = send(m, msgs.RunStarted{PID: 1, Log: "/tmp/l", Events: "/tmp/e"},
		msgs.EventsRead{Events: []events.Event{ev(0, "phase", "P0", "start", ""), ev(1, "phase", "P0", "ok", "")}},
		msgs.RunExited{Code: 0}, msgs.EventsRead{})
	if m.screen != Restart || c.doctor != 0 {
		t.Fatalf("screen %d doctor %d", m.screen, c.doctor)
	}
	if got := m.Content(); !strings.Contains(got, "wsl.exe --terminate Arch") || !strings.Contains(got, "umbra bootstrap resume") {
		t.Errorf("restart commands missing:\n%s", got)
	}
}

func TestExistingUserIsNamedAndBackSkipsAccountForUsers(t *testing.T) {
	env := fixtureEnv("umbra", theme.TrueColor, "en")
	env.Root = true
	m := send(started(t, env, 80, 24), msgs.Users{Names: []string{"rocker"}})
	if m.acct.User != "rocker" {
		t.Errorf("existing user not named: %q", m.acct.User)
	}
	n := started(t, fixtureEnv("umbra", theme.TrueColor, "en"), 80, 24)
	n, _ = press(n, "enter", "enter", "esc")
	if n.screen != Profile {
		t.Errorf("a regular user goes back from components to profile, got %d", n.screen)
	}
	o := fixtureEnv("umbra", theme.None, "en")
	o.Root, o.Platform = true, "arch"
	r, _ := press(started(t, o, 80, 24), "enter")
	if r.screen != Boot || !strings.Contains(r.Content(), "Running as root outside WSL") {
		t.Errorf("root on native Arch must stop at boot")
	}
}

func TestRerunStartsFromTheStoredSelection(t *testing.T) {
	m := started(t, fixtureEnv("umbra", theme.TrueColor, "en"), 80, 24)
	m = send(m, msgs.Stored{Found: true, Profile: "work", Theme: "lux", Components: []string{"shell", "prompt"}})
	if m.d.Sel.Profile != "work" || m.d.Sel.Variant != "lux" || !m.d.Installed["shell"] || len(m.d.Sel.Chosen) != 2 {
		t.Fatalf("stored not applied: %+v installed %v", m.d.Sel, m.d.Installed)
	}
	m, _ = press(m, "enter", "enter", "down", "space")
	if !m.d.Sel.Chosen["shell"] {
		t.Error("an installed item was unticked")
	}
	if !strings.Contains(m.Content(), "installed") {
		t.Error("installed tag missing")
	}
	m, _ = press(m, "down", "space") // prompt is installed too; nvim is next
	m, _ = press(m, "down", "space")
	if !m.d.Sel.Chosen["nvim"] {
		t.Error("a new item cannot be added on a re-run")
	}
	env := fixtureEnv("void", theme.TrueColor, "en")
	env.ThemeSet = true
	m2 := send(started(t, env, 80, 24), msgs.Stored{Found: true, Theme: "lux", Components: []string{"shell"}})
	if m2.d.Sel.Variant != "void" {
		t.Errorf("UM_THEME must win over the stored theme: %s", m2.d.Sel.Variant)
	}
}

func TestBootWaitsForPendingFacts(t *testing.T) {
	var tm tea.Model = New(fixtureEnv("umbra", theme.None, "en"), Cmds{}, msgsPending()...)
	tm, _ = tm.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	tm, _ = tm.Update(msgs.Catalog{Cat: loadCat(t)})
	m, _ := press(tm.(Model), "enter")
	if m.screen != Boot {
		t.Fatal("left boot while the access check was pending")
	}
	m = send(m, msgs.Batch(slowFacts))
	m, _ = press(m, "enter")
	if m.screen != Profile {
		t.Fatal("did not leave boot after the facts")
	}
}

func msgsPending() []msgs.ScanFact {
	return []msgs.ScanFact{{Key: "scan.access", State: msgs.FactPending}}
}

// Goldens of the run screens, with fixed times.
func runScreens(t *testing.T) map[string]string {
	c := &calls{}
	out := map[string]string{}
	m := toRun(t, c, true)
	m = send(m, msgs.RunStarted{PID: 1, Log: "~/.local/state/um/setup-20261105T100000Z.log", Events: "/tmp/e"},
		msgs.EventsRead{Events: []events.Event{
			ev(0, "phase", shell, "start", ""), ev(1, "log", shell, "info", "installing zsh"), ev(72, "phase", shell, "ok", ""),
			ev(72, "phase", prompt, "start", ""), ev(73, "log", prompt, "info", "Installing starship"), ev(74, "log", prompt, "warn", "slow mirror"),
		}}, msgs.Tick{Now: t0.Add(80 * time.Second)})
	m.r.Spin = 0
	out["run"] = m.Content()
	m, _ = press(m, "ctrl+c")
	out["run_stopask"] = m.Content()
	m, _ = press(m, "n")
	m = send(m, msgs.EventsRead{Events: []events.Event{ev(76, "phase", prompt, "ok", "")}}, msgs.RunExited{Code: 0}, msgs.EventsRead{},
		msgs.DoctorDone{OK: true, Tail: []string{"ok 03_shell", "ok 04_prompt"}})
	out["done"] = m.Content()
	f := toRun(t, &calls{}, true)
	f = send(f, msgs.RunStarted{PID: 1, Log: "~/.local/state/um/setup-x.log", Events: "/tmp/e"},
		msgs.EventsRead{Events: []events.Event{ev(0, "phase", shell, "start", ""), ev(2, "phase", shell, "fail", "zsh is missing")}},
		msgs.RunExited{Code: 1}, msgs.EventsRead{}, msgs.LogTail{Lines: []string{"[INFO] installing zsh", "[ERROR] gate shell failed: zsh is missing"}})
	out["failed"] = f.Content()
	env := fixtureEnv("umbra", theme.TrueColor, "en")
	env.Root, env.Distro = true, "Arch"
	r := send(started(t, env, 80, 24, fakeCmds(&calls{})), msgs.Users{})
	r, _ = press(r, "enter", "enter")
	r = typeText(r, "umbra")
	r, _ = press(r, "tab")
	r = typeText(r, "pw")
	r, _ = press(r, "tab")
	r = typeText(r, "pw")
	out["account"] = r.Content()
	r, _ = press(r, "enter", "enter", "enter", "enter")
	r = send(r, msgs.RunStarted{PID: 1, Log: "/root/.local/state/um/setup-x.log", Events: "/tmp/e"}, msgs.RunExited{Code: 0}, msgs.EventsRead{})
	out["restart"] = r.Content()
	return out
}

func TestRunGoldens(t *testing.T) {
	for name, content := range runScreens(t) {
		checkGolden(t, "run_"+name, content)
		for i, l := range strings.Split(content, "\n") {
			if w := visibleWidth(l); w != 80 {
				t.Errorf("%s line %d: width %d", name, i, w)
			}
		}
	}
}

func TestRunAccentShare(t *testing.T) {
	roles := theme.Roles["umbra"]
	neutral := map[string]bool{}
	for _, r := range []string{"fg", "fgMuted", "border", "ok", "warn", "error", "info", "link"} {
		neutral[sgr(roles[r])] = true
	}
	for name, content := range runScreens(t) {
		accent, _, _ := cells(content, neutral)
		if share := 100 * float64(accent) / float64(80*24); share > 10 {
			t.Errorf("%s: accent %.1f%% of the screen", name, share)
		}
	}
}
