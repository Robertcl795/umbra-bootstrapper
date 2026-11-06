package screens

import (
	"path"
	"strings"

	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/ui"
)

// ── make default ─────────────────────────────────────────────────────────────
// Plan installer-packages-shell, T4 (R5): after a passed run, before Done. It shows the chosen
// shell and, when PowerShell 7 was picked, Windows Terminal's default profile, each with what is
// the default now; nothing changes until the user presses enter (ADR 0043 as amended: the user
// confirms the default profile). Esc keeps everything as it is.

// Row ids of Make default.
const (
	DefaultLogin = "login" // the login shell (shell/default.sh --shell)
	DefaultWT    = "wt"    // Windows Terminal's default profile (shell/default.sh --wt-pwsh7)
)

// Default is the state of Make default.
type Default struct {
	Shell    string // the chosen shell, "" when none is set up (or on Omarchy, ADR 0011)
	WT       bool   // PowerShell 7 was picked
	Known    bool   // the status is in
	Status   msgs.DefaultStatus
	Off      map[string]bool // rows the user unticked
	Applying bool
}

// loginNow is the name of the current login shell (bash for /bin/bash).
func (d Default) loginNow() string { return path.Base(d.Status.Login) }

// Rows are the rows Make default shows: a change it can make, or (Windows Terminal without a
// PowerShell 7 profile yet) a hint.
func (d Default) Rows() []string {
	var rows []string
	if d.Shell != "" && d.loginNow() != d.Shell {
		rows = append(rows, DefaultLogin)
	}
	if d.WT && !(d.Status.WTPwsh7 != "" && strings.EqualFold(d.Status.WTDefault, d.Status.WTPwsh7)) {
		rows = append(rows, DefaultWT)
	}
	return rows
}

// Can reports whether a row is a change Make default can make.
func (d Default) Can(row string) bool { return row != DefaultWT || d.Status.WTPwsh7 != "" }

// Apply is what enter changes: the shell ("" none) and whether Windows Terminal's default.
func (d Default) Apply() (shell string, wt bool) {
	for _, r := range d.Rows() {
		if !d.Can(r) || d.Off[r] {
			continue
		}
		switch r {
		case DefaultLogin:
			shell = d.Shell
		case DefaultWT:
			wt = true
		}
	}
	return shell, wt
}

// DefaultView is the rows, what each sets and what is the default now.
func DefaultView(c ui.Ctx, d Default, cursor int) []string {
	bw := bodyW(c)
	w := bw - 4
	var lines []string
	for _, l := range ui.Words(c.T("default.ask"), w) {
		lines = append(lines, c.Th.R("fg", l))
	}
	lines = append(lines, "")
	if !d.Known {
		lines = append(lines, c.Th.R("fgMuted", c.T("default.checking")))
	}
	if d.Applying {
		lines = append(lines, c.Th.R("fgMuted", c.T("default.applying")))
	}
	type row struct{ id, label, want, now string }
	var rows []row
	lw, ww := 0, 0
	for _, r := range d.Rows() {
		x := row{id: r}
		switch r {
		case DefaultLogin:
			x.label, x.want, x.now = c.T("default.login"), shellName(d.Shell), d.loginNow()
		case DefaultWT:
			x.label, x.want, x.now = c.T("default.wt"), c.T("default.wt.want"), c.T("default.wt.other")
		}
		lw, ww = max(lw, ui.Width(x.label)), max(ww, ui.Width(x.want))
		rows = append(rows, x)
	}
	for i, x := range rows {
		box, role := "[■] ", "fg"
		if !d.Can(x.id) || d.Off[x.id] {
			box, role = "[ ] ", "fgMuted"
		}
		cols := box + ui.Fit(x.label, lw+2) + ui.Fit(x.want, ww+2)
		now := c.T("default.now", "v", x.now)
		lines = append(lines, ui.Row(c, i == cursor, c.Th.R(role, cols)+c.Th.R("fgMuted", now), cols+now, w))
		if !d.Can(x.id) {
			for _, l := range ui.Words(c.T("default.wt.missing"), w-6) {
				lines = append(lines, "      "+c.Th.R("warn", l))
			}
		}
	}
	return append([]string{""}, ui.Panel(c, c.T("default.title"), lines, bw, 0, false)...)
}

// DefaultKeys lists the footer keys of Make default.
func DefaultKeys(c ui.Ctx) []ui.Key {
	return []ui.Key{{Key: "↑↓", Desc: c.T("key.move")}, {Key: "space", Desc: c.T("key.toggle")},
		{Key: "enter", Desc: c.T("key.makedefault")}, {Key: "esc", Desc: c.T("key.keep")}}
}

// DefaultKey moves or toggles; enter is Next (apply the ticked rows), esc is Back (keep all).
func DefaultKey(key string, cursor int, d Default) (int, map[string]bool, Action) {
	off := map[string]bool{}
	for k, v := range d.Off {
		off[k] = v
	}
	rows := d.Rows()
	n := len(rows)
	if d.Applying || !d.Known {
		return cursor, off, None
	}
	switch key {
	case "up", "k":
		return (cursor + n - 1) % max(n, 1), off, None
	case "down", "j":
		return (cursor + 1) % max(n, 1), off, None
	case "space":
		if cursor < n && d.Can(rows[cursor]) {
			off[rows[cursor]] = !off[rows[cursor]]
		}
	case "enter":
		return cursor, off, Next
	case "esc", "q":
		return cursor, off, Back
	}
	return cursor, off, None
}
