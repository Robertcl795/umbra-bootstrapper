// Package app is umbra-setup's root Bubble Tea model (ux-spec §2.1). It routes messages to the
// screens and owns all state. It is pure: effects arrive injected as Cmds (Elm rules E1–E5).
package app

import (
	"slices"

	tea "charm.land/bubbletea/v2"

	"github.com/Robertcl795/umbra-bootstrapper/internal/i18n"
	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/screens"
	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
	"github.com/Robertcl795/umbra-bootstrapper/internal/ui"
)

// Screen ids, in step order (ui.Steps).
type Screen int

const (
	Boot Screen = iota
	Profile
	Components
	Theme
	Review
)

// MinW and MinH are the smallest terminal the screens are drawn for.
const (
	MinW = 80
	MinH = 24
)

// Cmds are the effects the app may start, injected by main (and by tests).
type Cmds struct {
	Init   []tea.Cmd               // scan facts and the catalog read
	Glitch func(frame int) tea.Cmd // the next boot glitch frame; nil = no motion
}

// Result is how the program ended.
type Result struct {
	Action screens.Action // Install, DryRun, or Quit (cancelled)
	Args   []string       // bootstrap.sh arguments for Install and DryRun
}

// Model is the whole program state.
type Model struct {
	d      screens.Data
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
}

// New returns the first model for an environment.
func New(env sys.Env, cmds Cmds) Model {
	d := screens.Data{Env: env}
	d.Sel = screens.Selection{Profile: "personal", Chosen: map[string]bool{}, Variant: env.Theme.Name}
	return Model{d: d, tr: i18n.New(env.Lang), cmds: cmds, tcur: max(0, slices.Index(theme.Variants, env.Theme.Name))}
}

// Result returns how the program ended.
func (m Model) Result() Result { return m.result }

// Init starts the effects: scan, catalog and the glitch.
func (m Model) Init() tea.Cmd {
	cmds := append([]tea.Cmd(nil), m.cmds.Init...)
	if m.cmds.Glitch != nil && !m.d.Env.NoMotion {
		cmds = append(cmds, m.cmds.Glitch(1))
	}
	return tea.Batch(cmds...)
}

// Update is the only place state changes (E1).
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
	case msgs.ScanFact:
		m.d.Facts = append(m.d.Facts, msg)
	case msgs.Catalog:
		m.d.Cat, m.d.Ready = msg.Cat, true
		m.d.Items = screens.Offered(msg.Cat, m.d.Env)
		m.d.Sel = screens.Defaults(m.d)
	case msgs.CatalogErr:
		m.d.CatErr = msg.Err
	case msgs.GlitchTick:
		if m.glitch < 0 || msg.Frame >= 3 {
			m.glitch = 0
			return m, nil
		}
		m.glitch = msg.Frame
		return m, m.cmds.Glitch(msg.Frame + 1)
	case tea.KeyPressMsg:
		return m.key(msg.String())
	}
	return m, nil
}

func (m Model) key(k string) (tea.Model, tea.Cmd) {
	if k == "ctrl+c" {
		m.result = Result{Action: screens.Quit}
		return m, tea.Quit
	}
	if m.small() {
		if k == "q" {
			m.result = Result{Action: screens.Quit}
			return m, tea.Quit
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
		}
	case Components:
		m.ccur, m.d.Sel.Chosen, a = screens.ComponentsKey(k, m.ccur, m.d)
	case Theme:
		m.tcur, a = screens.ThemeKey(k, m.tcur)
		m.d.Sel.Variant = theme.Variants[m.tcur]
	case Review:
		m.bcur, a = screens.ReviewKey(k, m.bcur, m.d)
	}
	switch a {
	case screens.Quit:
		m.result = Result{Action: screens.Quit}
		return m, tea.Quit
	case screens.Install, screens.DryRun:
		m.result = Result{Action: a, Args: m.d.Args()}
		return m, tea.Quit
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
	}
	return ui.Frame(c, right, int(m.screen), body, keys)
}

// View draws the model in the alternate screen, on the variant's background (truecolor).
func (m Model) View() tea.View {
	v := tea.NewView(m.Content())
	v.AltScreen = true
	v.BackgroundColor = m.d.Env.Theme.With(m.d.Sel.Variant).Background()
	return v
}
