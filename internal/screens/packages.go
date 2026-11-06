package screens

import (
	"strings"

	"github.com/Robertcl795/umbra-bootstrapper/internal/catalog"
	"github.com/Robertcl795/umbra-bootstrapper/internal/ui"
)

// ── packages: what an item installs (packages.tsv), and the editor ───────────
// Plan installer-packages-shell, R1–R3: every item lists its packages; items with optional
// packages (Q1: packages, lang, k8s) open an editor on e. Packages the item needs stay ticked.

// Packages are the packages.tsv rows of item id on this platform, in table order.
func (d Data) Packages(id string) []catalog.Package { return d.Pkgs.For(id, d.Env.Platform) }

// Editable reports whether item id has packages the user may leave out.
func (d Data) Editable(id string) bool { return d.Pkgs.Editable(id, d.Env.Platform) }

// leftOut counts the packages of item id the user left out.
func (d Data) leftOut(id string) int {
	n := 0
	for _, r := range d.Packages(id) {
		if r.Skip && d.Sel.SkipPkgs[r.Name] {
			n++
		}
	}
	return n
}

// room is the body rows a panel may use: the frame's body less the blank top line, the borders
// and one blank row above the footer.
func room(c ui.Ctx) int { return c.H - 8 }

// pkgLines lists the packages for the detail panel in at most n lines: "· name: description",
// a left-out one muted and crossed. When they do not fit, the last line says how many more.
func pkgLines(c ui.Ctx, d Data, id string, n int) []string {
	rows := d.Packages(id)
	lang := d.Env.Lang
	var out []string
	show := len(rows)
	if show > n {
		show = max(0, n-1)
	}
	for _, r := range rows[:show] {
		if r.Skip && d.Sel.SkipPkgs[r.Name] {
			out = append(out, c.Th.R("fgMuted", "✕ "+r.Name+": "+r.Desc[lang]))
			continue
		}
		out = append(out, c.Th.R("fg", "· "+r.Name)+c.Th.R("fgMuted", ": "+r.Desc[lang]))
	}
	more := len(rows) - show
	switch {
	case more > 0 && d.Editable(id):
		out = append(out, c.Th.R("link", c.T("pkg.more.edit", "n", itoa(more))))
	case more > 0:
		out = append(out, c.Th.R("fgMuted", c.T("pkg.more", "n", itoa(more))))
	case d.Editable(id) && len(out) < n:
		out = append(out, c.Th.R("link", c.T("pkg.edit")))
	}
	return out
}

// PackagesView is the editor of item id: one row per package, a window around the cursor.
func PackagesView(c ui.Ctx, d Data, id string, cursor int) []string {
	bw := bodyW(c)
	rows := d.Packages(id)
	lang := d.Env.Lang
	nameW := 0
	for _, r := range rows {
		nameW = max(nameW, ui.Width(r.Name))
	}
	nameW = min(nameW, 24)
	visible := max(1, room(c)-2)
	start := 0
	if len(rows) > visible {
		start = min(max(0, cursor-visible/2), len(rows)-visible)
	}
	end := min(len(rows), start+visible)
	var lines []string
	n, needed := 0, 0
	for _, r := range rows {
		switch {
		case !r.Skip:
			needed++
			n++
		case !d.Sel.SkipPkgs[r.Name]:
			n++
		}
	}
	for i := start; i < end; i++ {
		r := rows[i]
		name := r.Name + strings.Repeat(" ", max(0, nameW-ui.Width(r.Name)))
		var styled, plain string
		switch {
		case !r.Skip: // needed: always ticked, marked before its description so it never cuts off
			tag := "(" + c.T("pkg.needed") + ") "
			plain = "[■] " + name + "  " + tag + r.Desc[lang]
			styled = c.Th.R("fgMuted", "[■] ") + c.Th.R("fg", name) + c.Th.R("warn", "  "+tag) + c.Th.R("fgMuted", r.Desc[lang])
		case d.Sel.SkipPkgs[r.Name]:
			plain = "[ ] " + name + "  " + r.Desc[lang]
			styled = c.Th.R("fgMuted", plain)
		default:
			plain = "[■] " + name + "  " + r.Desc[lang]
			styled = c.Th.R("fg", "[■] "+name) + c.Th.R("fgMuted", "  "+r.Desc[lang])
		}
		lines = append(lines, ui.Row(c, i == cursor, styled, plain, bw-4))
	}
	count := c.T("pkg.count", "n", itoa(n), "total", itoa(len(rows)), "needed", itoa(needed))
	if len(rows) > visible {
		count += " · " + c.T("pkg.window", "a", itoa(start+1), "b", itoa(end))
	}
	lines = append(lines, "", c.Th.R("fgMuted", count))
	label := id
	for _, it := range d.Items {
		if it.ID == id {
			label = it.Label[lang]
		}
	}
	return append([]string{""}, ui.Panel(c, c.T("pkg.title", "item", strings.ToUpper(label)), lines, bw, 0, false)...)
}

// PackagesKeys lists the footer keys of the editor.
func PackagesKeys(c ui.Ctx) []ui.Key {
	return []ui.Key{{Key: "↑↓", Desc: c.T("key.move")}, {Key: "space", Desc: c.T("key.toggle")}, {Key: "a", Desc: c.T("key.all")},
		{Key: "n", Desc: c.T("key.none")}, {Key: "esc", Desc: c.T("key.done")}}
}

// PackagesKey moves, toggles or closes the editor (Back). skip is changed in a copy; needed
// packages never change.
func PackagesKey(key string, cursor int, d Data, id string) (int, map[string]bool, Action) {
	skip := map[string]bool{}
	for k, v := range d.Sel.SkipPkgs {
		skip[k] = v
	}
	rows := d.Packages(id)
	n := len(rows)
	switch key {
	case "up", "k":
		return (cursor + n - 1) % max(n, 1), skip, None
	case "down", "j":
		return (cursor + 1) % max(n, 1), skip, None
	case "space":
		if cursor < n && rows[cursor].Skip {
			name := rows[cursor].Name
			skip[name] = !skip[name]
		}
	case "a":
		for _, r := range rows {
			delete(skip, r.Name)
		}
	case "n":
		for _, r := range rows {
			if r.Skip {
				skip[r.Name] = true
			}
		}
	case "esc", "enter":
		return cursor, skip, Back
	case "q":
		return cursor, skip, Quit
	}
	return cursor, skip, None
}
