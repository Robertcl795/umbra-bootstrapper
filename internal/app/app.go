// Package app is umbra-setup's root Bubble Tea model (ux-spec §2.1). It routes messages to the
// screens and owns all state. It is pure: effects arrive injected as Cmds (Elm rules E1–E5).
package app

import (
	"slices"
	"strconv"
	"strings"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/ansi"

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
	Account // only as root on WSL: the user stage 1 creates
	Components
	Shell // the shell choice and its extras (plan installer-packages-shell, R4)
	Theme
	Review
	Run
	MakeDefault // after a passed run: the chosen shell (and PowerShell 7) as the default (plan T4)
	Done
	Restart
	Failed
)

// step is the step-row position of each screen.
var step = map[Screen]int{Boot: 0, Profile: 1, Account: 1, Components: 2, Shell: 3, Theme: 4, Review: 5, Run: 6,
	MakeDefault: 7, Done: 8, Restart: 8, Failed: 6}

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
	Shine        func(frame int) tea.Cmd // the next corona sweep frame (the rest when frame is 1)
	Tick         func() tea.Cmd          // 100 ms, only while something is pending or running
	SudoValidate func() tea.Cmd
	SudoRefresh  func() tea.Cmd
	Start        func(args []string, password string) tea.Cmd // password: for stage 1's new user, or ""
	Wait         func(pid int) tea.Cmd
	ReadEvents   func(path string, offset int64) tea.Cmd
	Stop         func(stopFile string) tea.Cmd
	Doctor       func(logPath string, env []string) tea.Cmd // env: plan.DoctorEnv
	LogTail      func(path string) tea.Cmd
	// Make default (shell/default.sh): the status, then the change the user confirmed.
	DefaultStatus func() tea.Cmd
	MakeDefault   func(shell string, wt bool) tea.Cmd
}

// Result is how the program ended.
type Result struct {
	Action screens.Action // DryRun, Quit (cancelled before Install), or Next (a run ended)
	Args   []string       // install.sh arguments
	Code   int            // exit code for main
}

// Model is the whole program state.
type Model struct {
	d       screens.Data
	r       screens.Run
	tr      i18n.Func
	cmds    Cmds
	screen  Screen
	pcur    int
	ccur    int
	editing bool // the package editor of the item under ccur is open (on Components)
	ecur    int
	scur    int
	def     screens.Default
	dcur    int
	tcur    int
	bcur    int
	glitch  int
	shine   int  // the corona sweep frame, 0 = still
	shining bool // a ShineTick is on its way
	w, h    int
	result  Result

	acct      screens.Account
	users     []string
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

	resume    *sys.Resume // stage 2: run the staged selection without asking (--resume)
	resumed   bool
	sudoKnown bool
}

// New returns the first model for an environment. pending are scan lines that will arrive.
func New(env sys.Env, cmds Cmds, pending ...msgs.ScanFact) Model {
	d := screens.Data{Env: env, Facts: pending}
	d.Sel = screens.Selection{Profile: "personal", Chosen: map[string]bool{}, Variant: env.Theme.Name}
	d.Passwordless = env.Root
	return Model{d: d, r: screens.Run{Distro: env.Distro}, tr: i18n.New(env.Lang), cmds: cmds,
		tcur: max(0, slices.Index(theme.Variants, env.Theme.Name)), shining: cmds.Shine != nil && !env.NoMotion}
}

// Resuming makes the model run stage 2: boot scans, then the staged selection starts on its own
// once the catalog and the sudo state are known; there is no Profile…Review.
func (m Model) Resuming(r sys.Resume) Model {
	m.resume = &r
	m.d.Resume = true
	return m
}

// maybeResume starts the staged run once everything it needs is in.
func (m *Model) maybeResume() tea.Cmd {
	if m.resume == nil || m.resumed || !m.d.Ready || !m.sudoKnown || m.screen != Boot {
		return nil
	}
	m.resumed, m.touched = true, true
	m.d.Sel.Profile = m.resume.Profile
	if m.resume.Shell != "" {
		m.d.Sel.Shell = m.resume.Shell
	}
	m.d.Sel.Chosen = map[string]bool{}
	for _, id := range plan.ItemsFromComponents(m.d.Cat, m.d.Env.Platform, m.resume.Components) {
		m.d.Sel.Chosen[id] = true
	}
	return m.install()
}

// install validates sudo (once) and starts the run.
func (m *Model) install() tea.Cmd {
	m.d.SudoErr = ""
	if m.d.Passwordless || m.cmds.SudoValidate == nil {
		return m.start()
	}
	return m.cmds.SudoValidate()
}

// logoVisible: the wordmark (boot) or the header's sweep (run) is on screen.
func (m Model) logoVisible() bool { return m.screen == Boot || m.screen == Run }

// shineTick advances the sweep; off the logo, or without motion, the chain ends.
func (m *Model) shineTick(f int) tea.Cmd {
	if m.d.Env.NoMotion || m.cmds.Shine == nil || !m.logoVisible() {
		m.shine, m.shining = 0, false
		return nil
	}
	m.shining = true
	if f > ui.ShineFrames {
		m.shine = 0
		return m.cmds.Shine(1)
	}
	m.shine = f
	return m.cmds.Shine(f + 1)
}

// Result returns how the program ended.
func (m Model) Result() Result { return m.result }

// Init starts the effects: scan, catalog, stored selection, the glitch and the spinner.
func (m Model) Init() tea.Cmd {
	cmds := append([]tea.Cmd(nil), m.cmds.Init...)
	if m.cmds.Glitch != nil && !m.d.Env.NoMotion {
		cmds = append(cmds, m.cmds.Glitch(1))
	}
	if m.shining {
		cmds = append(cmds, m.cmds.Shine(1))
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
		m.d.Cat, m.d.Pkgs, m.d.Ready = msg.Cat, msg.Pkgs, true
		m.defaults()
		cmd = m.maybeResume()
	case msgs.CatalogErr:
		m.d.CatErr = msg.Err
	case msgs.Access:
		ok := msg.OK
		m.d.Env.Access = &ok
		m.defaults()
	case msgs.Sudo:
		m.d.Passwordless = m.d.Env.Root || msg.Passwordless
		m.sudoKnown = true
		cmd = m.maybeResume()
	case msgs.Stored:
		m.stored = msg
		m.defaults()
	case msgs.Users:
		m.users = msg.Names
		if m.acct.User == "" {
			m.acct = screens.AccountFor(msg.Names)
		}
	case msgs.GlitchTick:
		if m.glitch < 0 || msg.Frame >= 3 {
			m.glitch = 0
			return m, nil
		}
		m.glitch = msg.Frame
		return m, m.cmds.Glitch(msg.Frame + 1)
	case msgs.ShineTick:
		cmd = m.shineTick(msg.Frame)
	case msgs.Tick:
		m.r.Now = msg.Now
		m.d.Spin++
		m.r.Spin++
		m.ticking = false
	case msgs.DefaultStatus:
		m.def.Status, m.def.Known = msg, true
		if len(m.def.Rows()) == 0 {
			m.screen = Done
		}
	case msgs.DefaultDone:
		m.def.Applying = false
		m.r.Defaults = msg.Lines
		if msg.Err != "" {
			m.r.Defaults = append(m.r.Defaults, "! "+msg.Err)
		}
		m.screen = Done
	case msgs.SudoReady:
		m.d.Passwordless = true
		if m.screen == MakeDefault {
			cmd = m.cmds.MakeDefault(m.def.Apply())
			break
		}
		cmd = m.start()
	case msgs.SudoFailed:
		if m.screen == MakeDefault {
			m.def.Applying = false
			m.r.Defaults = []string{"! " + m.tr("review.sudo.failed", "err", msg.Err)}
			m.screen = Done
			break
		}
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
		if len(m.stored.SkipPackages) > 0 {
			sel.SkipPkgs = map[string]bool{}
			for _, name := range m.stored.SkipPackages {
				sel.SkipPkgs[name] = true
			}
		}
		if m.stored.Shell != "" {
			sel.Shell = m.stored.Shell
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
	if m.resume != nil && m.screen == Boot { // stage 2 starts on its own; enter retries a failed sudo
		switch {
		case k == "q":
			return m.quit(screens.Quit, 130)
		case k == "enter" && m.d.SudoErr != "" && m.resumed:
			return m, m.install()
		}
		return m, nil
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
		if m.editing {
			id := m.d.On(screens.ScreenComponents)[m.ccur].ID
			m.ecur, m.d.Sel.SkipPkgs, a = screens.PackagesKey(k, m.ecur, m.d, id)
			if k == "space" || k == "a" || k == "n" {
				m.touched = true
			}
			if a == screens.Back {
				m.editing, a = false, screens.None
			}
			break
		}
		before := len(m.d.Sel.Chosen)
		m.ccur, m.d.Sel.Chosen, a = screens.ComponentsKey(k, m.ccur, m.d)
		if k == "space" || k == "a" || k == "n" || before != len(m.d.Sel.Chosen) {
			m.touched = true
		}
		if a == screens.Edit {
			m.editing, m.ecur, a = true, 0, screens.None
		}
	case Account:
		m.acct, a = screens.AccountKey(k, m.acct)
		if a == screens.Next {
			m.d.Extra = []string{"--user", m.acct.User}
		}
	case Shell:
		m.scur, m.d.Sel.Chosen, m.d.Sel.Shell, a = screens.ShellKey(k, m.scur, m.d)
		if k == "space" {
			m.touched = true
		}
	case Theme:
		m.tcur, a = screens.ThemeKey(k, m.tcur)
		m.d.Sel.Variant = theme.Variants[m.tcur]
		m.touched = true
	case Review:
		m.bcur, a = screens.ReviewKey(k, m.bcur, m.d)
	case MakeDefault:
		var da screens.Action
		m.dcur, m.def.Off, da = screens.DefaultKey(k, m.dcur, m.def)
		switch da {
		case screens.Next:
			shell, wt := m.def.Apply()
			if (shell == "" && !wt) || m.cmds.MakeDefault == nil {
				m.screen = Done
				return m, nil
			}
			m.def.Applying = true
			if shell != "" && m.cmds.SudoValidate != nil {
				// usermod needs sudo, and its timestamp may be gone (finish.sh removed stage 2's
				// rule): renew it on the terminal first; SudoReady then makes the change.
				return m, m.cmds.SudoValidate()
			}
			return m, m.cmds.MakeDefault(shell, wt)
		case screens.Back:
			m.r.Defaults = []string{m.tr("default.kept")}
			m.screen = Done
		}
		return m, nil
	case Restart:
		if k == "enter" && m.driven() {
			return m.quit(screens.Next, RestartCode) // the driver terminates and runs stage 2
		}
		if k == "enter" && m.wsl() {
			m.result = Result{Action: screens.Leave, Args: m.args}
			return m, tea.Quit
		}
		if k == "enter" || k == "q" || k == "esc" {
			return m.quit(screens.Next, m.endCode())
		}
	case Done, Failed:
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
		return m, m.install()
	case screens.Next:
		m.screen++
		if m.screen == Account && !m.needAccount() {
			m.screen++
		}
		m.enter()
	case screens.Back:
		if m.screen > Boot {
			m.screen--
			if m.screen == Account && !m.needAccount() {
				m.screen--
			}
			m.enter()
		}
	}
	return m, nil
}

// RestartCode is the exit code that tells install.ps1 "stage 1 done, restart the distro"
// (ADR 0042).
const RestartCode = 10

// driven: install.ps1 runs this stage and does the restart itself (UM_DRIVER=ps1).
func (m Model) driven() bool { return m.d.Env.Driver == "ps1" }

func (m Model) wsl() bool { return strings.HasPrefix(m.d.Env.Platform, "wsl-") }

// needAccount: root on WSL runs stage 1, which must be told the user (stage1.sh p2_pre).
func (m Model) needAccount() bool {
	return m.d.Env.Root && strings.HasPrefix(m.d.Env.Platform, "wsl-")
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
	ids := plan.Phases(m.d.Cat, m.d.Env.Platform, m.d.Plan().Items)
	if m.needAccount() { // stage 1: no chezmoi script runs before the restart
		ids = plan.Stage1
	}
	for _, id := range ids {
		m.r.Phases = append(m.r.Phases, screens.Phase{ID: id})
	}
	m.r.Started = m.r.Now // the last tick; the first event corrects it when earlier
	var shine tea.Cmd
	if !m.shining && m.cmds.Shine != nil && !m.d.Env.NoMotion {
		m.shining = true
		shine = m.cmds.Shine(1)
	}
	if m.cmds.Start == nil {
		return shine
	}
	password := ""
	if m.needAccount() {
		password = m.acct.Pass
	}
	return tea.Batch(shine, m.cmds.Start(m.args, password))
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

// phase returns the row of id. One the list did not have goes after the last phase that started
// (it runs now), so rows stay in the order they ran; the doctor stays last.
func (m *Model) phase(id string) int {
	at := 0
	for i, p := range m.r.Phases {
		if p.ID == id {
			return i
		}
		if p.State != screens.Waiting && p.ID != plan.Doctor {
			at = i + 1
		}
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
	case m.doctorEnded():
		// finish.sh (stage 2) already ran the doctor as a phase: no second one.
		return m.end()
	case m.cmds.Doctor == nil || m.resume != nil:
		m.dropDoctor()
		return m.end()
	}
	i := m.phase(plan.Doctor)
	m.r.Phases[i].State, m.r.Phases[i].Start = screens.Running, m.r.Now
	m.r.Current = plan.Doctor
	m.doctoring = true
	return m.cmds.Doctor(m.r.LogPath, plan.DoctorEnv(m.d.Cat, m.d.Env.Platform, m.d.Plan()))
}

// end follows a passed run: Make default when there is a default to ask about, else Done.
// Omarchy keeps its login shell (ADR 0011).
func (m *Model) end() tea.Cmd {
	shell := m.d.Plan().Shell
	if m.d.Env.Platform == "omarchy" {
		shell = ""
	}
	wt := false
	for _, it := range m.d.On(screens.ScreenShellExtra) {
		wt = wt || m.d.Sel.Chosen[it.ID]
	}
	if (shell == "" && !wt) || m.cmds.DefaultStatus == nil {
		m.screen = Done
		return nil
	}
	m.def, m.dcur, m.screen = screens.Default{Shell: shell, WT: wt}, 0, MakeDefault
	return m.cmds.DefaultStatus()
}

func (m Model) doctorEnded() bool {
	for _, p := range m.r.Phases {
		if p.ID == plan.Doctor {
			return p.State == screens.Passed
		}
	}
	return false
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
		return m.end()
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
	switch m.screen {
	case Boot:
		c.Shine = m.shine
	case Run:
		c.HeadShine = m.shine
	}
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
	case Account:
		body, keys = screens.AccountView(c, m.acct, m.users), screens.AccountKeys(c)
	case Components:
		if m.editing {
			body, keys = screens.PackagesView(c, m.d, m.d.On(screens.ScreenComponents)[m.ccur].ID, m.ecur), screens.PackagesKeys(c)
			break
		}
		body, keys = screens.ComponentsView(c, m.d, m.ccur), screens.ComponentsKeys(c)
	case Shell:
		body, keys = screens.ShellView(c, m.d, m.scur), screens.ShellKeys(c)
	case Theme:
		body, keys = screens.ThemeView(c, m.tcur), screens.ThemeKeys(c)
	case Review:
		body, keys = screens.ReviewView(c, m.d, m.bcur), screens.ReviewKeys(c)
	case Run:
		body, keys = screens.RunView(c, m.r), screens.RunKeys(c, m.r)
	case MakeDefault:
		body, keys = screens.DefaultView(c, m.def, m.dcur), screens.DefaultKeys(c)
	case Done:
		body, keys = screens.DoneView(c, m.r, m.d.Sel.Chosen[umbraAI(m.d)]), screens.EndKeys(c)
	case Restart:
		body, keys = screens.RestartView(c, m.r), screens.RestartKeys(c, m.wsl(), m.driven())
	case Failed:
		command := plan.Command(m.args)
		if m.resume != nil {
			command = "umbra bootstrap resume"
		}
		body, keys = screens.FailedView(c, m.r, command), screens.EndKeys(c)
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

// View draws the model in the alternate screen, on the variant's background (truecolor). The
// window title names the screen and its state; the terminal tab shows the step, and tests can
// wait on it (an OSC title is written whole, unlike cells the renderer only changes).
func (m Model) View() tea.View {
	th := m.d.Env.Theme.With(m.d.Sel.Variant)
	content := m.Content()
	v := tea.NewView(ui.PaintBackground(content, th))
	v.AltScreen = true
	v.BackgroundColor = th.Background()
	v.Cursor = m.cursor(content)
	v.WindowTitle = m.Title()
	return v
}

// cursor is the terminal's own cursor in the account screen's focused field: a bar right after
// the text, blinking unless NO_MOTION (terminals keep it steady while keys arrive).
func (m Model) cursor(content string) *tea.Cursor {
	if m.screen != Account || m.small() {
		return nil
	}
	c := ui.Ctx{Th: m.d.Env.Theme.With(m.d.Sel.Variant), T: m.tr, W: m.w, H: m.h}
	label, dx := screens.AccountCursor(c, m.acct)
	for y, row := range strings.Split(ansi.Strip(content), "\n") {
		if i := strings.Index(row, label); i >= 0 {
			cur := tea.NewCursor(ansi.StringWidth(row[:i])+dx, y)
			cur.Shape, cur.Blink = tea.CursorBar, !m.d.Env.NoMotion
			return cur
		}
	}
	return nil
}

// Title is "Umbra setup · <screen>[ <state>]".
func (m Model) Title() string {
	name := map[Screen]string{Boot: "scan", Profile: "profile", Account: "account", Components: "components", Shell: "shell",
		Theme: "theme", Review: "review", Run: "run", MakeDefault: "default", Done: "done", Restart: "restart", Failed: "failed"}[m.screen]
	state := ""
	switch m.screen {
	case Boot:
		if screens.BootCanContinue(m.d) {
			state = "ready"
		}
	case Account:
		state = []string{"user", "password", "again"}[m.acct.Field]
	case Components:
		if m.editing {
			name, state = "editor", m.d.On(screens.ScreenComponents)[m.ccur].ID
			break
		}
		n, items := 0, m.d.On(screens.ScreenComponents)
		for _, it := range items {
			if m.d.Sel.Chosen[it.ID] {
				n++
			}
		}
		state = strconv.Itoa(n) + "/" + strconv.Itoa(len(items))
	case Shell:
		state = m.d.Plan().Shell
	case Theme:
		state = m.d.Sel.Variant
	case Review:
		state = strings.TrimPrefix(screens.Buttons[m.bcur], "btn.")
	}
	if state != "" {
		return "Umbra setup · " + name + " " + state
	}
	return "Umbra setup · " + name
}
