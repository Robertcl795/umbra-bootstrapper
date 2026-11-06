package screens

import (
	"slices"
	"strings"

	"github.com/Robertcl795/umbra-bootstrapper/internal/catalog"
	"github.com/Robertcl795/umbra-bootstrapper/internal/ui"
)

// ── shell ────────────────────────────────────────────────────────────────────
// Plan installer-packages-shell, R4: the catalog's shell items (screen "shell-choice") are a choice of
// shell, zsh or one its packages name ("shell=fish" rows); the "shell-extra" items (PowerShell 7
// on WSL) are boxes below it. Neither shows in Components.

// Screen values of the catalog.
const (
	ScreenComponents = "components"
	ScreenShell      = "shell-choice"
	ScreenShellExtra = "shell-extra"
)

// DefaultShell is the shell picked until the user picks another (ADR 0004: zsh first).
const DefaultShell = "zsh"

// NoShell is the row that leaves the shell item out (what unticking it in Components did).
const NoShell = "-"

// On returns the offered items of a screen, in menu order.
func (d Data) On(screen ...string) []catalog.Item {
	var out []catalog.Item
	for _, it := range d.Items {
		if slices.Contains(screen, it.Screen) {
			out = append(out, it)
		}
	}
	return out
}

// ShellRow is one row of the Shell screen: a shell of a choice item, or an extra item's box.
type ShellRow struct {
	Item  catalog.Item
	Shell string // the shell this row picks; "" for an extra
}

// ShellRows are the rows in order: each choice item's shells (zsh, then the ones its packages
// name, then "no shell setup"), then the extras.
func ShellRows(d Data) []ShellRow {
	var rows []ShellRow
	for _, it := range d.On(ScreenShell) {
		rows = append(rows, ShellRow{Item: it, Shell: DefaultShell})
		for _, s := range d.Pkgs.Shells(it.ID, d.Env.Platform) {
			if s != DefaultShell {
				rows = append(rows, ShellRow{Item: it, Shell: s})
			}
		}
		if !d.Installed[it.ID] {
			rows = append(rows, ShellRow{Item: it, Shell: NoShell})
		}
	}
	for _, it := range d.On(ScreenShellExtra) {
		rows = append(rows, ShellRow{Item: it})
	}
	return rows
}

// shellName is the label of a shell: Zsh, Fish.
func shellName(s string) string { return strings.ToUpper(s[:1]) + s[1:] }

// ShellView is the list (focused) and the detail of the row under the cursor.
func ShellView(c ui.Ctx, d Data, cursor int) []string {
	bw := bodyW(c)
	lw := bw/2 + 1
	rw := bw - lw - 1
	rows := ShellRows(d)
	var left []string
	extras := false
	for i, r := range rows {
		var box, label string
		role := "fgMuted"
		switch {
		case r.Shell == NoShell:
			box, label = "( ) ", c.T("shell.none")
			if !d.Sel.Chosen[r.Item.ID] {
				box, role = "(●) ", "fg"
			}
		case r.Shell != "":
			box, label = "( ) ", shellName(r.Shell)
			if d.Sel.Chosen[r.Item.ID] && d.Sel.Shell == r.Shell {
				box, role = "(●) ", "fg"
			}
		default:
			if !extras {
				left = append(left, "", c.Th.R("fgMuted", "  "+c.T("shell.windows")))
				extras = true
			}
			box, label = "[ ] ", c.T("shell.pwsh7")
			if d.Sel.Chosen[r.Item.ID] {
				box, role = "[■] ", "fg"
			}
		}
		left = append(left, ui.Row(c, i == cursor, c.Th.R(role, box+label), box+label, lw-4))
	}
	var right []string
	if cursor < len(rows) {
		r := rows[cursor]
		title, summary := strings.ToUpper(r.Item.ID), r.Item.Summary[d.Env.Lang]
		pkgs := d.Pkgs.For(r.Item.ID, d.Env.Platform)
		switch r.Shell {
		case NoShell:
			title, summary, pkgs = strings.ToUpper(c.T("shell.none")), c.T("shell.none.detail"), nil
		case "":
		default:
			title, summary = strings.ToUpper(r.Shell), c.T("shell."+r.Shell)
			pkgs = d.Pkgs.ForShell(r.Item.ID, d.Env.Platform, r.Shell)
		}
		right = []string{c.Th.B("fg", title)}
		for _, l := range ui.Words(summary, rw-4) {
			right = append(right, c.Th.R("fg", l))
		}
		right = append(right, "")
		for _, p := range pkgs {
			right = append(right, c.Th.R("fg", "· "+p.Name)+c.Th.R("fgMuted", ": "+p.Desc[d.Env.Lang]))
		}
	}
	h := max(len(left), len(right))
	return append([]string{""}, ui.Side(ui.Panel(c, c.T("shell.title"), left, lw, h, true), lw,
		ui.Panel(c, c.T("comp.detail"), right, rw, h, false), 1)...)
}

// ShellKeys lists the footer keys of the Shell screen.
func ShellKeys(c ui.Ctx) []ui.Key {
	return []ui.Key{{Key: "↑↓", Desc: c.T("key.move")}, {Key: "space", Desc: c.T("key.choose")},
		{Key: "enter", Desc: c.T("key.next")}, {Key: "esc", Desc: c.T("key.back")}}
}

// ShellKey moves, picks a shell (its item is then installed) or toggles an extra. chosen is
// changed in a copy.
func ShellKey(key string, cursor int, d Data) (int, map[string]bool, string, Action) {
	chosen := map[string]bool{}
	for k, v := range d.Sel.Chosen {
		chosen[k] = v
	}
	shell := d.Sel.Shell
	rows := ShellRows(d)
	n := len(rows)
	switch key {
	case "up", "k":
		return (cursor + n - 1) % max(n, 1), chosen, shell, None
	case "down", "j":
		return (cursor + 1) % max(n, 1), chosen, shell, None
	case "space":
		if cursor < n {
			r := rows[cursor]
			switch {
			case r.Shell == NoShell:
				chosen[r.Item.ID] = false
			case r.Shell != "":
				chosen[r.Item.ID], shell = true, r.Shell
			case !d.Installed[r.Item.ID]:
				chosen[r.Item.ID] = !chosen[r.Item.ID]
			}
		}
	case "enter":
		return cursor, chosen, shell, Next
	case "esc":
		return cursor, chosen, shell, Back
	case "q":
		return cursor, chosen, shell, Quit
	}
	return cursor, chosen, shell, None
}
