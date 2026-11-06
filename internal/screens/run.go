package screens

import (
	"strings"
	"time"

	"github.com/Robertcl795/umbra-bootstrapper/internal/plan"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
	"github.com/Robertcl795/umbra-bootstrapper/internal/ui"
)

// PhaseState is how a phase row is drawn.
type PhaseState int

const (
	Waiting PhaseState = iota
	Running
	Passed
	Failed
	Skipped   // its component is not selected
	Unchanged // chezmoi did not run it (inputs unchanged), or the run ended first
)

// Phase is one row of the run screen.
type Phase struct {
	ID         string
	State      PhaseState
	Start, End time.Time
	Msg        string // the fail message
}

// LogLine is one log event.
type LogLine struct{ Phase, Level, Text string }

// Run is what the run, done, restart and failed screens read.
type Run struct {
	Phases   []Phase
	Current  string
	Logs     []LogLine
	Started  time.Time
	Now      time.Time
	LogPath  string
	Spin     int
	StopAsk  bool
	Stopping bool
	Stopped  bool // the run was stopped by the user
	Doctor   []string
	Tail     []string // last lines of the log (failed)
	Distro   string   // WSL_DISTRO_NAME, for the restart commands
}

var spinner = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

func dur(d time.Duration) string {
	if d < time.Minute {
		return itoa(int(d.Seconds())) + "s"
	}
	return itoa(int(d.Minutes())) + "m" + pad2(int(d.Seconds())%60) + "s"
}

func pad2(n int) string {
	if n < 10 {
		return "0" + itoa(n)
	}
	return itoa(n)
}

func phaseName(c ui.Ctx, id string) string {
	if id == plan.Doctor {
		return c.T("run.doctor")
	}
	return plan.Short(id)
}

// Counts returns how many phases ended, passed (ok, skip, unchanged) and the total.
func (r Run) Counts() (ended, passed, total int) {
	for _, p := range r.Phases {
		total++
		switch p.State {
		case Passed, Skipped, Unchanged:
			ended++
			passed++
		case Failed:
			ended++
		}
	}
	return ended, passed, total
}

// FailedPhase is the first failed phase, if any.
func (r Run) FailedPhase() (Phase, bool) {
	for _, p := range r.Phases {
		if p.State == Failed {
			return p, true
		}
	}
	return Phase{}, false
}

func (r Run) currentName(c ui.Ctx) string {
	if r.Current == "" {
		return "—"
	}
	return phaseName(c, r.Current)
}

// RunView is the phase list (focused), the log of the current phase and the progress bar.
func RunView(c ui.Ctx, r Run) []string {
	bw := bodyW(c)
	lw := 34
	rw := bw - lw - 1
	h := c.H - 10
	var left []string
	first := 0
	for i, p := range r.Phases { // keep the running phase in view
		if p.ID == r.Current && i >= h {
			first = i - h + 1
		}
	}
	for _, p := range r.Phases[first:min(len(r.Phases), first+h)] {
		glyph, role := "○ ", "fgMuted"
		t := ""
		switch p.State {
		case Running:
			glyph, role = spinner[r.Spin%len(spinner)]+" ", "info"
			t = dur(r.Now.Sub(p.Start))
		case Passed:
			glyph, role = "● ", "ok"
			t = dur(p.End.Sub(p.Start))
		case Failed:
			glyph, role = "✕ ", "error"
			t = dur(p.End.Sub(p.Start))
		case Skipped:
			glyph, t = "– ", c.T("run.skipped")
		case Unchanged:
			glyph, t = "– ", c.T("run.unchanged")
		}
		nameRole := "fg"
		if p.State == Waiting || p.State == Skipped || p.State == Unchanged {
			nameRole = "fgMuted"
		}
		name := ui.Fit(phaseName(c, p.ID), lw-4-2-9)
		left = append(left, c.Th.R(role, glyph)+c.Th.R(nameRole, name)+c.Th.R("fgMuted", leftPad(t, 9)))
	}
	var lines []LogLine
	for _, l := range r.Logs {
		if l.Phase == r.Current || (r.Current == "" && l.Phase == "") {
			lines = append(lines, l)
		}
	}
	if len(lines) > h {
		lines = lines[len(lines)-h:]
	}
	var right []string
	for _, l := range lines {
		tag, role := "[INFO] ", "fgMuted"
		switch l.Level {
		case "warn":
			tag, role = "[WARN] ", "warn"
		case "error":
			tag, role = "[ERR]  ", "error"
		}
		right = append(right, c.Th.R(role, tag)+c.Th.R("fg", l.Text))
	}
	out := append([]string{""}, ui.Side(ui.Panel(c, c.T("run.phases"), left, lw, h, true), lw,
		ui.Panel(c, c.T("run.log", "phase", r.currentName(c)), right, rw, h, false), 1)...)
	ended, _, total := r.Counts()
	out = append(out, Bar(c, ended, total, 40)+" "+c.Th.R("fg", itoa(ended)+"/"+itoa(total))+
		c.Th.R("fgMuted", " · "+dur(r.Now.Sub(r.Started))), c.Th.R("fgMuted", c.T("run.logat", "path", r.LogPath)))
	switch {
	case r.Stopping:
		out = append(out, c.Th.R("warn", "! ")+c.Th.R("fg", c.T("run.stopping", "phase", r.currentName(c))))
	case r.StopAsk:
		out = append(out, c.Th.R("warn", "? ")+c.Th.R("fg", c.T("run.stop.ask", "phase", r.currentName(c)))+c.Th.R("fgMuted", "  y/n"))
	}
	return out
}

func leftPad(s string, w int) string {
	if n := ui.Width(s); n < w {
		return strings.Repeat(" ", w-n) + s
	}
	return s
}

// Bar is the progress bar in gradient.corona (ANSI-16: accent; no color: # and .).
func Bar(c ui.Ctx, done, total, w int) string {
	fill := 0
	if total > 0 {
		fill = w * done / total
	}
	if c.Th.Profile == theme.None {
		return strings.Repeat("#", fill) + strings.Repeat(".", w-fill)
	}
	var b strings.Builder
	cols := c.Th.Corona(w)
	for i := 0; i < fill; i++ {
		if cols != nil {
			b.WriteString(c.Th.Style("fg").Foreground(cols[i]).Render("█"))
		} else {
			b.WriteString(c.Th.R("accent", "█"))
		}
	}
	b.WriteString(c.Th.R("border", strings.Repeat("░", w-fill)))
	return b.String()
}

// RunKeys lists the footer keys of run.
func RunKeys(c ui.Ctx, r Run) []ui.Key {
	if r.StopAsk {
		return []ui.Key{{Key: "y", Desc: c.T("key.stop")}, {Key: "n", Desc: c.T("key.keepgoing")}}
	}
	return []ui.Key{{Key: "ctrl+c", Desc: c.T("key.stopafter")}}
}

// DoneView is the result, the doctor and the next steps.
func DoneView(c ui.Ctx, r Run, umbraAI bool) []string {
	bw := bodyW(c)
	_, passed, total := r.Counts()
	out := []string{"", c.Th.R("ok", "✓ ") + c.Th.B("fg", c.T("done.ok", "n", itoa(passed), "total", itoa(total))), ""}
	doctor := r.Doctor
	if len(doctor) == 0 {
		doctor = []string{c.T("done.doctor.quiet")}
	}
	var d []string
	for _, l := range doctor {
		d = append(d, c.Th.R("fgMuted", l))
	}
	out = append(out, ui.Panel(c, c.T("done.doctor"), d, bw, 0, false)...)
	next := []string{c.Th.R("fg", c.T("done.newterm"))}
	if umbraAI {
		next = append(next, c.Th.R("info", ui.Fit("um doctor", 36))+c.Th.R("fgMuted", c.T("done.umdoctor")))
	}
	next = append(next, c.Th.R("info", ui.Fit("UM_THEME=lux chezmoi init --apply", 36))+c.Th.R("fgMuted", c.T("done.variant")))
	out = append(out, "")
	out = append(out, ui.Panel(c, c.T("done.next"), next, bw, 0, false)...)
	return append(out, "", c.Th.R("fgMuted", c.T("run.logat", "path", r.LogPath)))
}

// RestartView is the WSL restart point after stage 1 (bootstrapper README).
func RestartView(c ui.Ctx, r Run) []string {
	bw := bodyW(c)
	distro := r.Distro
	if distro == "" {
		distro = "<distro>"
	}
	lines := []string{
		c.Th.B("fg", c.T("restart.title")), "",
		c.Th.R("fgMuted", c.T("restart.windows")),
		"  " + c.Th.R("info", "wsl.exe --terminate "+distro),
		"  " + c.Th.R("info", "wsl.exe -d "+distro), "",
		c.Th.R("fgMuted", c.T("restart.then")),
		"  " + c.Th.R("info", "umbra bootstrap resume"),
		"  " + c.Th.R("info", "umbra bootstrap status") + c.Th.R("fgMuted", "  "+c.T("restart.status")),
	}
	return append([]string{""}, append(ui.Panel(c, c.T("restart.panel"), lines, bw, 0, false), "", c.Th.R("fgMuted", c.T("run.logat", "path", r.LogPath)))...)
}

// FailedView names the failed phase, its message and the end of the log.
func FailedView(c ui.Ctx, r Run, command string) []string {
	bw := bodyW(c)
	var out []string
	if r.Stopped {
		out = []string{"", c.Th.R("warn", "! ") + c.Th.B("fg", c.T("failed.stopped", "phase", r.currentName(c)))}
	} else {
		p, ok := r.FailedPhase()
		name := c.T("failed.unknown")
		if ok {
			name = phaseName(c, p.ID)
		}
		out = []string{"", c.Th.R("error", "✕ ") + c.Th.B("fg", c.T("failed.title", "phase", name))}
		if ok && p.Msg != "" {
			out = append(out, "  "+c.Th.R("error", p.Msg))
		}
	}
	out = append(out, "")
	var tail []string
	for _, l := range r.Tail {
		tail = append(tail, c.Th.R("fgMuted", l))
	}
	out = append(out, ui.Panel(c, c.T("failed.log"), tail, bw, 0, false)...)
	out = append(out, "")
	for _, l := range ui.Words(c.T("failed.again"), bw) {
		out = append(out, c.Th.R("fg", l))
	}
	out = append(out, ui.Next(c, command, bw)...)
	return append(out, c.Th.R("fgMuted", c.T("run.logat", "path", r.LogPath)))
}

// EndKeys are the keys of done, restart and failed.
func EndKeys(c ui.Ctx) []ui.Key { return []ui.Key{{Key: "enter", Desc: c.T("key.exit")}} }

// RestartKeys: on WSL, enter leaves the distro (umbra-setup terminates it) and q only closes.
func RestartKeys(c ui.Ctx, wsl bool) []ui.Key {
	if !wsl {
		return EndKeys(c)
	}
	return []ui.Key{{Key: "enter", Desc: c.T("key.leavewsl")}, {Key: "q", Desc: c.T("key.stay")}}
}
