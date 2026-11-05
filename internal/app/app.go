// Package app is umbra-setup's root Bubble Tea model (ux-spec §2.1). It routes messages to the
// screens and owns all state. It is pure: effects arrive injected as Cmds (Elm rules E1–E5).
package app

import (
	"slices"

	tea "charm.land/bubbletea/v2"

	"github.com/Robertcl795/umbra-bootstrapper/internal/events"
	"github.com/Robertcl795/umbra-bootstrapper/internal/i18n"
	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/plan"
	"github.com/Robertcl795/umbra-bootstrapper/internal/screens"
	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
	"github.com/Robertcl795/umbra-bootstrapper/internal/ui"
)

// Screen ids.
type Screen int

const (
	Boot Screen = iota
	Profile
	Components
	Theme
	Review
	Run
	Done
	Restart
	Failed
)

// step is the step-row position of each screen.
var step = map[Screen]int{Boot: 0, Profile: 1, Components: 2, Theme: 3, Review: 4, Run: 5, Done: 6, Restart: 6, Failed: 5}

// MinW and MinH are the smallest terminal the screens are drawn for.
const (
	MinW = 80
	MinH = 24
)

// Cmds are the effects the app may start, injected by main (and by tests). A nil field is an
// effect the caller does not offer; the app then skips it.
type Cmds struct {
	Init         []tea.Cmd               // fast facts, slow facts, catalog, stored selection
	Glitch       func(frame int) tea.Cmd // the next boot glitch frame
	Tick         func() tea.Cmd          // 100 ms, only while something is pending or running
	SudoValidate func() tea.Cmd
	SudoRefresh  func() tea.Cmd
	Start        func(args []string) tea.Cmd
	Wait         func(pid int) tea.Cmd
	ReadEvents   func(path string, offset int64) tea.Cmd
	Stop         func(stopFile string) tea.Cmd
	Doctor       func(logPath string) tea.Cmd
	LogTail      func(path string) tea.Cmd
}

// Result is how the program ended.
type Result struct {
	Action screens.Action // DryRun, Quit (cancelled before Install), or Next (a run ended)
	Args   []string       // install.sh arguments
	Code   int            // exit code for main
}

// Model is the whole program state.
type Model struct {
	d      screens.Data
	r      screens.Run
	tr     i18n.Func
	cmds   Cmds
	screen Screen
	pcur   int
	ccur   int
	tcur   int
	bcur   int
	glitch int
	w, h   int
	result Result

	stored    msgs.Stored
	touched   bool // the user changed the selection: stored data and defaults no longer apply
	ticking   bool
	pid       int
	evPath    string
	stopPath  string
	offset    int64
	exited    bool
	exitCode  int
	stopReq   bool
	doctoring bool
	args      []string
}

// New returns the first model for an environment. pending are scan lines that will arrive.
func New(env sys.Env, cmds Cmds, pending ...msgs.ScanFact) Model {
	d := screens.Data{Env: env, Facts: pending}
	d.Sel = screens.Selection{Profile: "personal", Chosen: map[string]bool{}, Variant: env.Theme.Name}
	d.Passwordless = env.Root
	return Model{d: d, r: screens.Run{Distro: env.Distro}, tr: i18n.New(env.Lang), cmds: cmds,
		tcur: max(0, slices.Index(theme.Variants, env.Theme.Name))}
}

// Result returns how the program ended.
func (m Model) Result() Result { return m.result }

// Init starts the effects: scan, catalog, stored selection, the glitch and the spinner.
func (m Model) Init() tea.Cmd {
	cmds := append([]tea.Cmd(nil), m.cmds.Init...)
	if m.cmds.Glitch != nil && !m.d.Env.NoMotion {
		cmds = append(cmds, m.cmds.Glitch(1))
	}
	return tea.Batch(cmds...)
}

// Update is the only place state changes (E1).
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	switch msg := msg.(type) {
	case msgs.Batch:
		var cmds []tea.Cmd
		var tm tea.Model = m
		for _, sub := range msg {
			var c tea.Cmd
			tm, c = tm.Update(sub)
			cmds = append(cmds, c)
		}
		return tm, tea.Batch(cmds...)
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
	case msgs.ScanFact:
		m.setFact(msg)
	case msgs.Catalog:
		m.d.Cat, m.d.Ready = msg.Cat, true
		m.defaults()
	case msgs.CatalogErr:
		m.d.CatErr = msg.Err
	case msgs.Access:
		ok := msg.OK
		m.d.Env.Access = &ok
		m.defaults()
	case msgs.Sudo:
		m.d.Passwordless = m.d.Env.Root || msg.Passwordless
	case msgs.Stored:
		m.stored = msg
		m.defaults()
	case msgs.GlitchTick:
		if m.glitch < 0 || msg.Frame >= 3 {
			m.glitch = 0
			return m, nil
		}
		m.glitch = msg.Frame
		return m, m.cmds.Glitch(msg.Frame + 1)
	case msgs.Tick:
		m.r.Now = msg.Now
		m.d.Spin++
		m.r.Spin++
		m.ticking = false
	case msgs.SudoReady:
		m.d.Passwordless = true
		cmd = m.start()
	case msgs.SudoFailed:
		m.d.SudoErr = msg.Err
	case msgs.RunStarted:
		m.pid, m.evPath, m.r.LogPath, m.stopPath = msg.PID, msg.Events, msg.Log, msg.Stop
		cmd = tea.Batch(call(m.cmds.Wait, msg.PID), callRead(m.cmds.ReadEvents, msg.Events, 0), m.refresh())
	case msgs.RunErr:
		m.r.Tail = []string{m.tr("err.run", "err", msg.Err)}
		m.screen = Failed
	case msgs.SudoRefreshed:
		cmd = m.refresh()
	case msgs.EventsRead:
		cmd = m.events(msg)
	case msgs.RunExited:
		m.exited, m.exitCode = true, msg.Code
	case msgs.DoctorDone:
		cmd = m.doctorDone(msg)
	case msgs.LogTail:
		m.r.Tail = msg.Lines
	case tea.KeyPressMsg:
		var tm tea.Model
		tm, cmd = m.key(msg.String())
		m = tm.(Model)
	}
	return m, tea.Batch(cmd, m.tick())
}

func call(f func(int) tea.Cmd, pid int) tea.Cmd {
	if f == nil {
		return nil
	}
	return f(pid)
}

func callRead(f func(string, int64) tea.Cmd, path string, off int64) tea.Cmd {
	if f == nil {
		return nil
	}
	return f(path, off)
}

// tick asks for the next 100 ms tick while a scan line is pending or a run is going.
func (m *Model) tick() tea.Cmd {
	if m.ticking || m.cmds.Tick == nil || !(m.pending() || m.screen == Run) {
		return nil
	}
	m.ticking = true
	return m.cmds.Tick()
}

func (m Model) pending() bool {
	for _, f := range m.d.Facts {
		if f.State == msgs.FactPending {
			return true
		}
	}
	return false
}

func (m *Model) setFact(f msgs.ScanFact) {
	for i := range m.d.Facts {
		if m.d.Facts[i].Key == f.Key {
			m.d.Facts[i] = f
			return
		}
	}
	m.d.Facts = append(m.d.Facts, f)
}

// defaults recomputes the offered items and, until the user changes anything, the selection:
// the stored chezmoi selection of a previous run, else the catalog defaults.
func (m *Model) defaults() {
	if !m.d.Ready {
		return
	}
	m.d.Items = screens.Offered(m.d.Cat, m.d.Env)
	if m.touched {
		return
	}
	sel := screens.Defaults(m.d)
	m.d.Installed = map[string]bool{}
	if m.stored.Found {
		sel.Chosen = map[string]bool{}
		for _, id := range plan.ItemsFromComponents(m.d.Cat, m.d.Env.Platform, m.stored.Components) {
			sel.Chosen[id] = true
			m.d.Installed[id] = true
		}
		if m.stored.Profile != "" {
			sel.Profile = m.stored.Profile
		}
		if m.stored.Theme != "" && !m.d.Env.ThemeSet && slices.Contains(theme.Variants, m.stored.Theme) {
			sel.Variant = m.stored.Theme
		}
	}
	m.d.Sel = sel
	m.tcur = max(0, slices.Index(theme.Variants, sel.Variant))
}

func (m Model) key(k string) (tea.Model, tea.Cmd) {
	if m.screen == Run {
		return m.runKey(k)
	}
	if k == "ctrl+c" {
		return m.quit(screens.Quit, 130)
	}
	if m.small() {
		if k == "q" {
			return m.quit(screens.Quit, 130)
		}
		return m, nil
	}
	m.glitch = -1 // any key stops the glitch
	var a screens.Action
	switch m.screen {
	case Boot:
		a = screens.BootKey(k, m.d)
	case Profile:
		m.pcur, a = screens.ProfileKey(k, m.pcur)
		if a == screens.Next {
			m.d.Sel.Profile = screens.Profiles[m.pcur]
			m.touched = true
		}
	case Components:
		before := len(m.d.Sel.Chosen)
		m.ccur, m.d.Sel.Chosen, a = screens.ComponentsKey(k, m.ccur, m.d)
		if k == "space" || k == "a" || k == "n" || before != len(m.d.Sel.Chosen) {
			m.touched = true
		}
	case Theme:
		m.tcur, a = screens.ThemeKey(k, m.tcur)
		m.d.Sel.Variant = theme.Variants[m.tcur]
		m.touched = true
	case Review:
		m.bcur, a = screens.ReviewKey(k, m.bcur, m.d)
	case Done, Restart, Failed:
		if k == "enter" || k == "q" || k == "esc" {
			return m.quit(screens.Next, m.endCode())
		}
	}
	switch a {
	case screens.Quit:
		return m.quit(screens.Quit, 130)
	case screens.DryRun:
		m.result = Result{Action: screens.DryRun, Args: m.d.Args()}
		return m, tea.Quit
	case screens.Install:
		m.args = m.d.Args()
		m.d.SudoErr = ""
		if m.d.Passwordless || m.cmds.SudoValidate == nil {
			return m, m.start()
		}
		return m, m.cmds.SudoValidate()
	case screens.Next:
		m.screen++
		m.enter()
	case screens.Back:
		if m.screen > Boot {
			m.screen--
			m.enter()
		}
	}
	return m, nil
}

func (m Model) quit(a screens.Action, code int) (tea.Model, tea.Cmd) {
	m.result = Result{Action: a, Args: m.args, Code: code}
	return m, tea.Quit
}

func (m Model) endCode() int {
	switch m.screen {
	case Failed:
		if m.r.Stopped {
			return 130
		}
		return 1
	}
	return 0
}

// start opens the run screen and starts install.sh.
func (m *Model) start() tea.Cmd {
	m.screen = Run
	m.r.Phases = nil
	for _, id := range plan.Phases(m.d.Cat, m.d.Env.Platform, m.d.Plan().Items) {
		m.r.Phases = append(m.r.Phases, screens.Phase{ID: id})
	}
	m.r.Started = m.r.Now // the last tick; the first event corrects it when earlier
	if m.cmds.Start == nil {
		return nil
	}
	return m.cmds.Start(m.args)
}

func (m Model) refresh() tea.Cmd {
	if m.d.Env.Root || m.cmds.SudoRefresh == nil || m.exited {
		return nil
	}
	return m.cmds.SudoRefresh()
}

// events applies new events; once the child exited and the file is drained, the run ends.
func (m *Model) events(msg msgs.EventsRead) tea.Cmd {
	var cmds []tea.Cmd
	for _, ev := range msg.Events {
		cmds = append(cmds, m.apply(ev))
	}
	m.offset = msg.Offset
	if m.exited && len(msg.Events) == 0 {
		cmds = append(cmds, m.finish())
		return tea.Batch(cmds...)
	}
	return tea.Batch(append(cmds, callRead(m.cmds.ReadEvents, m.evPath, m.offset))...)
}

func (m *Model) apply(ev events.Event) tea.Cmd {
	if m.r.Started.IsZero() || ev.At.Before(m.r.Started) {
		m.r.Started = ev.At
	}
	if ev.At.After(m.r.Now) {
		m.r.Now = ev.At
	}
	if ev.Kind == "log" {
		m.r.Logs = append(m.r.Logs, screens.LogLine{Phase: ev.Phase, Level: ev.State, Text: ev.Message})
		if len(m.r.Logs) > 200 {
			m.r.Logs = m.r.Logs[len(m.r.Logs)-200:]
		}
		return nil
	}
	i := m.phase(ev.Phase)
	p := &m.r.Phases[i]
	switch ev.State {
	case "start":
		p.State, p.Start = screens.Running, ev.At
		m.r.Current = ev.Phase
		return nil
	case "ok":
		p.State = screens.Passed
	case "fail":
		p.State, p.Msg = screens.Failed, ev.Message
	case "skip":
		p.State = screens.Skipped
	}
	p.End = ev.At
	if p.Start.IsZero() {
		p.Start = ev.At
	}
	return nil
}

// phase returns the row of id, adding it before the doctor when the catalog did not list it.
func (m *Model) phase(id string) int {
	for i, p := range m.r.Phases {
		if p.ID == id {
			return i
		}
	}
	at := len(m.r.Phases)
	if at > 0 && m.r.Phases[at-1].ID == plan.Doctor {
		at--
	}
	m.r.Phases = slices.Insert(m.r.Phases, at, screens.Phase{ID: id})
	return at
}

// finish decides what follows the child's exit: doctor, restart, done or failed.
func (m *Model) finish() tea.Cmd {
	for i := range m.r.Phases {
		if m.r.Phases[i].State == screens.Waiting && m.r.Phases[i].ID != plan.Doctor {
			m.r.Phases[i].State = screens.Unchanged
		}
	}
	switch {
	case m.exitCode != 0:
		m.screen = Failed
		return callTail(m.cmds.LogTail, m.r.LogPath)
	case m.d.Env.Root:
		m.dropDoctor()
		m.screen = Restart
		return nil
	case m.cmds.Doctor == nil:
		m.dropDoctor()
		m.screen = Done
		return nil
	}
	i := m.phase(plan.Doctor)
	m.r.Phases[i].State, m.r.Phases[i].Start = screens.Running, m.r.Now
	m.r.Current = plan.Doctor
	m.doctoring = true
	return m.cmds.Doctor(m.r.LogPath)
}

func callTail(f func(string) tea.Cmd, p string) tea.Cmd {
	if f == nil {
		return nil
	}
	return f(p)
}

func (m *Model) dropDoctor() {
	m.r.Phases = slices.DeleteFunc(m.r.Phases, func(p screens.Phase) bool { return p.ID == plan.Doctor })
}

func (m *Model) doctorDone(msg msgs.DoctorDone) tea.Cmd {
	i := m.phase(plan.Doctor)
	m.r.Phases[i].End = m.r.Now
	m.r.Doctor = msg.Tail
	m.doctoring = false
	if msg.OK {
		m.r.Phases[i].State = screens.Passed
		m.screen = Done
		return nil
	}
	m.r.Phases[i].State = screens.Failed
	m.r.Phases[i].Msg = m.tr("run.doctor.failed")
	m.r.Tail = msg.Tail
	m.screen = Failed
	return nil
}

// runKey: ctrl+c asks to stop after the current phase; y or a second ctrl+c confirms. The stop
// file makes bash start nothing else; the running phase finishes (common.sh phase_start).
func (m Model) runKey(k string) (tea.Model, tea.Cmd) {
	switch {
	case m.r.StopAsk && (k == "y" || k == "ctrl+c"):
		m.r.StopAsk, m.r.Stopping, m.stopReq, m.r.Stopped = false, true, true, true
		if m.cmds.Stop == nil {
			return m, nil
		}
		return m, m.cmds.Stop(m.stopPath)
	case m.r.StopAsk && (k == "n" || k == "esc"):
		m.r.StopAsk = false
	case k == "ctrl+c" && !m.stopReq:
		m.r.StopAsk = true
	}
	return m, nil
}

// enter sets a screen's cursor from the selection when the screen opens.
func (m *Model) enter() {
	switch m.screen {
	case Profile:
		m.pcur = max(0, slices.Index(screens.Profiles, m.d.Sel.Profile))
	case Theme:
		m.tcur = max(0, slices.Index(theme.Variants, m.d.Sel.Variant))
	case Review:
		m.bcur = screens.ReviewStart(m.d)
	}
}

func (m Model) small() bool { return m.w < MinW || m.h < MinH }

// Content is the screen as text (golden tests read it); View wraps it.
func (m Model) Content() string {
	if m.w == 0 {
		return ""
	}
	c := ui.Ctx{Th: m.d.Env.Theme.With(m.d.Sel.Variant), T: m.tr, W: m.w, H: m.h}
	if m.small() {
		return screens.SmallView(c)
	}
	right := m.d.Env.Platform + " · " + m.d.Sel.Profile + " · " + m.d.Sel.Variant + " · " + m.d.Env.Version
	var body []string
	var keys []ui.Key
	switch m.screen {
	case Boot:
		body, keys = screens.BootView(c, m.d, max(m.glitch, 0)), screens.BootKeys(c, m.d)
	case Profile:
		body, keys = screens.ProfileView(c, m.d, m.pcur), screens.ProfileKeys(c)
	case Components:
		body, keys = screens.ComponentsView(c, m.d, m.ccur), screens.ComponentsKeys(c)
	case Theme:
		body, keys = screens.ThemeView(c, m.tcur), screens.ThemeKeys(c)
	case Review:
		body, keys = screens.ReviewView(c, m.d, m.bcur), screens.ReviewKeys(c)
	case Run:
		body, keys = screens.RunView(c, m.r), screens.RunKeys(c, m.r)
	case Done:
		body, keys = screens.DoneView(c, m.r, m.d.Sel.Chosen[umbraAI(m.d)]), screens.EndKeys(c)
	case Restart:
		body, keys = screens.RestartView(c, m.r), screens.EndKeys(c)
	case Failed:
		body, keys = screens.FailedView(c, m.r, plan.Command(m.args)), screens.EndKeys(c)
	}
	return ui.Frame(c, right, step[m.screen], body, keys)
}

// umbraAI is the id of the item gated by Umbra AI access (the catalog's ai-access default).
func umbraAI(d screens.Data) string {
	for _, it := range d.Items {
		if it.Default == "ai-access" {
			return it.ID
		}
	}
	return ""
}

// View draws the model in the alternate screen, on the variant's background (truecolor).
func (m Model) View() tea.View {
	v := tea.NewView(m.Content())
	v.AltScreen = true
	v.BackgroundColor = m.d.Env.Theme.With(m.d.Sel.Variant).Background()
	return v
}
