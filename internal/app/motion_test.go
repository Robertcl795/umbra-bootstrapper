package app

import (
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/ansi"

	"github.com/Robertcl795/umbra-bootstrapper/internal/events"
	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/plan"
	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
	"github.com/Robertcl795/umbra-bootstrapper/internal/ui"
)

// shineCmds records the frames the app schedules.
func shineCmds(frames *[]int, c *calls) Cmds {
	cmds := fakeCmds(c)
	cmds.Shine = func(f int) tea.Cmd {
		*frames = append(*frames, f)
		return func() tea.Msg { return nil }
	}
	return cmds
}

func motionEnv() sys.Env {
	env := fixtureEnv("umbra", theme.TrueColor, "en")
	env.NoMotion = false
	return env
}

func TestShineSweepsTheWordmarkAndRests(t *testing.T) {
	var frames []int
	m := started(t, motionEnv(), 80, 24, shineCmds(&frames, &calls{}))
	still := m.Content()
	m = send(m, msgs.ShineTick{Frame: 1})
	if m.shine != 1 || len(frames) != 1 || frames[0] != 2 {
		t.Fatalf("frame 1: shine %d, scheduled %v", m.shine, frames)
	}
	m = send(m, msgs.ShineTick{Frame: ui.ShineFrames / 2})
	mid := m.Content()
	if mid == still {
		t.Fatal("the wordmark looks the same in the middle of a sweep")
	}
	if ansi.Strip(mid) != ansi.Strip(still) {
		t.Fatal("the sweep changed the text, not only its color")
	}
	frames = nil
	m = send(m, msgs.ShineTick{Frame: ui.ShineFrames + 1})
	if m.shine != 0 || len(frames) != 1 || frames[0] != 1 {
		t.Fatalf("after the last frame: shine %d, scheduled %v (want rest, then frame 1)", m.shine, frames)
	}
	if m.Content() != still {
		t.Fatal("at rest the screen is not the still wordmark")
	}
}

func TestShineStopsOffTheLogoAndRestartsOnRun(t *testing.T) {
	var frames []int
	c := &calls{}
	m := started(t, motionEnv(), 80, 24, shineCmds(&frames, c))
	m = send(m, msgs.ShineTick{Frame: 1})
	m, _ = press(m, "enter") // profile: no wordmark
	frames = nil
	m = send(m, msgs.ShineTick{Frame: 2})
	if len(frames) != 0 || m.shine != 0 || m.shining {
		t.Fatalf("off the logo: shine %d, scheduled %v", m.shine, frames)
	}
	m, _ = press(m, "enter", "n", "down", "space", "enter", "enter", "enter")
	m.d.Passwordless = true
	m, _ = press(m, "enter")
	if m.screen != Run || len(frames) != 1 || frames[0] != 1 {
		t.Fatalf("run: screen %d, scheduled %v", m.screen, frames)
	}
	still := m.Content()
	m = send(m, msgs.ShineTick{Frame: 3})
	head := func(s string) string { return strings.SplitN(s, "\n", 2)[0] }
	if head(m.Content()) == head(still) {
		t.Fatal("the header's UMBRA does not move during the run")
	}
}

func TestNoMotionMeansNoShine(t *testing.T) {
	var frames []int
	m := started(t, fixtureEnv("umbra", theme.TrueColor, "en"), 80, 24, shineCmds(&frames, &calls{}))
	m = send(m, msgs.ShineTick{Frame: 1})
	if len(frames) != 0 || m.shine != 0 {
		t.Fatalf("NoMotion: shine %d, scheduled %v", m.shine, frames)
	}
}

func TestSweepKeepsTheTextAndLeavesSpacesAlone(t *testing.T) {
	th := theme.New("umbra", theme.TrueColor)
	for f := 0; f <= ui.ShineFrames+1; f++ {
		got := ui.Sweep(th, "█ █ UMBRA", f)
		if ansi.Strip(got) != "█ █ UMBRA" {
			t.Fatalf("frame %d: %q", f, ansi.Strip(got))
		}
	}
	if ui.Sweep(theme.New("umbra", theme.None), "UMBRA", 4) != "UMBRA" {
		t.Fatal("no color: the sweep must be plain text")
	}
}

// ── resume (stage 2 through umbra-setup) ─────────────────────────────────────

func resumed(t *testing.T, c *calls, passwordless bool) Model {
	t.Helper()
	env := fixtureEnv("umbra", theme.TrueColor, "en")
	cmds := fakeCmds(c)
	var tm tea.Model = New(env, cmds, effects0()...).Resuming(sys.Resume{Components: []string{"shell", "prompt"}, Profile: "work"})
	tm, _ = tm.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	tm, _ = tm.Update(msgs.Catalog{Cat: loadCat(t)})
	m := tm.(Model)
	if m.screen != Boot || c.start != 0 {
		t.Fatalf("before sudo is known: screen %d start %d", m.screen, c.start)
	}
	if !strings.Contains(m.Content(), "Stage 2") {
		t.Fatalf("boot does not say it resumes stage 2:\n%s", m.Content())
	}
	m, _ = press(m, "enter")
	if m.screen != Boot {
		t.Fatalf("enter left boot while resuming: screen %d", m.screen)
	}
	return send(m, msgs.Sudo{Passwordless: passwordless})
}

func effects0() []msgs.ScanFact { return []msgs.ScanFact{{Key: "scan.sudo", State: msgs.FactPending}} }

func TestResumeRunsTheStagedSelectionWithoutAsking(t *testing.T) {
	c := &calls{}
	m := resumed(t, c, true)
	if m.screen != Run || c.start != 1 || c.sudo != 0 {
		t.Fatalf("screen %d start %d sudo %d", m.screen, c.start, c.sudo)
	}
	if m.d.Sel.Profile != "work" || !m.d.Sel.Chosen["shell"] || !m.d.Sel.Chosen["prompt"] || len(m.d.Sel.Chosen) != 2 {
		t.Fatalf("selection %+v", m.d.Sel)
	}
	ids := phaseIDs(m)
	if !strings.Contains(strings.Join(ids, ","), shell) || ids[len(ids)-1] != plan.Doctor {
		t.Fatalf("phases %v", ids)
	}
}

func TestResumeAsksSudoOnceWhenItIsNotFree(t *testing.T) {
	c := &calls{}
	m := resumed(t, c, false)
	if m.screen != Boot || c.sudo != 1 || c.start != 0 {
		t.Fatalf("screen %d sudo %d start %d", m.screen, c.sudo, c.start)
	}
	m = send(m, msgs.SudoReady{})
	if m.screen != Run || c.start != 1 {
		t.Fatalf("after sudo: screen %d start %d", m.screen, c.start)
	}
}

func TestResumeTakesTheDoctorFromFinishSh(t *testing.T) {
	c := &calls{}
	m := resumed(t, c, true)
	m = send(m, msgs.RunStarted{PID: 7, Log: "/tmp/s.log", Events: "/tmp/s.events"},
		msgs.EventsRead{Events: []events.Event{
			ev(0, "phase", shell, "start", ""), ev(2, "phase", shell, "ok", ""),
			ev(2, "phase", plan.Doctor, "start", ""), ev(4, "phase", plan.Doctor, "ok", ""),
		}, Offset: 10},
		msgs.RunExited{Code: 0}, msgs.EventsRead{Offset: 10})
	if m.screen != Done || c.doctor != 0 {
		t.Fatalf("screen %d, umbra-setup ran the doctor %d times (finish.sh already did)", m.screen, c.doctor)
	}
	if ids := phaseIDs(m); ids[len(ids)-1] != plan.Doctor {
		t.Fatalf("the doctor row was dropped: %v", ids)
	}
	if got := m.Title(); got != "Umbra setup · done" {
		t.Fatalf("title %q", got)
	}
}

func TestResumeFromEnv(t *testing.T) {
	get := func(k string) string {
		return map[string]string{"UM_COMPONENTS": "packages,shell", "UM_SKIP": "k8s", "UM_MODE": "work"}[k]
	}
	r := sys.ResumeFrom(get)
	if strings.Join(r.Components, ",") != "packages,shell" || strings.Join(r.Skip, ",") != "k8s" || r.Profile != "work" {
		t.Fatalf("%+v", r)
	}
	if r := sys.ResumeFrom(func(string) string { return "" }); r.Profile != "personal" || len(r.Components) != 0 {
		t.Fatalf("empty: %+v", r)
	}
}
