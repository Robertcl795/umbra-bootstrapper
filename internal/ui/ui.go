// Package ui draws the parts every screen shares (ux-spec §3): header, step row, rule, footer,
// panels and padding. Every function is pure: theme and text in, a string out (Elm rule E2).
package ui

import (
	"image/color"
	"strings"

	"charm.land/lipgloss/v2"
	"github.com/charmbracelet/x/ansi"

	"github.com/Robertcl795/umbra-bootstrapper/internal/i18n"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
)

// Steps are the step-row ids, in order (i18n keys "step.<id>").
var Steps = []string{"scan", "profile", "components", "theme", "review", "run", "done"}

// Ctx is what drawing needs.
type Ctx struct {
	Th theme.T
	T  i18n.Func
	W  int // terminal width
	H  int // terminal height
}

// Width is the visible width of s (ANSI aware).
func Width(s string) int { return lipgloss.Width(s) }

// Fit pads or cuts s to exactly w visible cells.
func Fit(s string, w int) string {
	if w <= 0 {
		return ""
	}
	if n := Width(s); n > w {
		return ansi.Truncate(s, w, "…")
	} else if n < w {
		return s + strings.Repeat(" ", w-n)
	}
	return s
}

// Header is "◢◤ UMBRA//SETUP" on the left and the facts on the right.
func Header(c Ctx, right string) string {
	th := c.Th
	left := th.R("accent2", "◢◤ ") + th.B("fg", "UMBRA") + th.R("accent2", "//") + th.R("fg", "SETUP")
	gap := c.W - Width(left) - Width(right)
	if gap < 1 {
		right = ansi.Truncate(right, max(0, c.W-Width(left)-1), "…")
		gap = 1
	}
	return left + strings.Repeat(" ", gap) + th.R("fgMuted", right)
}

// StepRow marks done steps ■, the current one ◆ (bold) and the next ones ◇.
func StepRow(c Ctx, current int) string {
	var parts []string
	for i, id := range Steps {
		name := c.T("step." + id)
		switch {
		case i < current:
			parts = append(parts, c.Th.R("fgMuted", "■ "+name))
		case i == current:
			parts = append(parts, c.Th.B("fg", "◆ "+name))
		default:
			parts = append(parts, c.Th.R("fgMuted", "◇ "+name))
		}
	}
	return Fit(strings.Join(parts, "  "), c.W)
}

// Rule is a full-width line in the border role.
func Rule(c Ctx) string { return c.Th.R("border", strings.Repeat("─", c.W)) }

// Key is one footer entry.
type Key struct{ Key, Desc string }

// Footer lists keys: the key bold, its description muted.
func Footer(c Ctx, keys []Key) string {
	var parts []string
	for _, k := range keys {
		parts = append(parts, c.Th.B("fg", k.Key)+" "+c.Th.R("fgMuted", k.Desc))
	}
	return Fit(strings.Join(parts, c.Th.R("border", "  ·  ")), c.W)
}

// Frame places header, step row, rule, body and footer on a W×H screen. The body is indented by
// one cell and cut or padded to the rows left.
func Frame(c Ctx, right string, step int, body []string, keys []Key) string {
	rows := []string{Header(c, right), StepRow(c, step), Rule(c)}
	room := c.H - len(rows) - 1
	for i := 0; i < room; i++ {
		line := ""
		if i < len(body) {
			line = " " + body[i]
		}
		rows = append(rows, Fit(line, c.W))
	}
	rows = append(rows, Footer(c, keys))
	return strings.Join(rows, "\n")
}

// Panel draws a box w cells wide around lines, at least minH body rows. Only screens with two or
// more panels mark one as focused (ux-spec §6.4: the gradient border is the view's accent, so a
// lone panel keeps the plain border and the 70/20/7/3 proportion holds). The focused panel has a
// heavy border in the activeBorder gradient (truecolor), the accent role (ANSI-16) or plain
// glyphs (no color); the others a light border in the border role. The title sits in the top
// border.
func Panel(c Ctx, title string, lines []string, w, minH int, focused bool) []string {
	body := append([]string(nil), lines...)
	for len(body) < minH {
		body = append(body, "")
	}
	h := len(body) + 2
	g := glyphs{"┌", "┐", "└", "┘", "─", "│"}
	if focused {
		g = glyphs{"┏", "┓", "┗", "┛", "━", "┃"}
	}
	var grid []color.Color
	if focused {
		grid = c.Th.BorderGrid(w, h)
	}
	paint := func(x, y int, s string) string {
		switch {
		case c.Th.Profile == theme.None:
			return s
		case focused && grid != nil:
			return lipgloss.NewStyle().Foreground(grid[y*w+x]).Render(s)
		case focused:
			return c.Th.R("accent", s)
		}
		return c.Th.R("border", s)
	}
	titleText := " " + title + " "
	tstyle := c.Th.R("fgMuted", titleText)
	if focused {
		tstyle = c.Th.B("fg", titleText)
	}
	tw := Width(titleText)
	var top strings.Builder
	top.WriteString(paint(0, 0, g.tl) + paint(1, 0, g.h) + tstyle)
	for x := 2 + tw; x < w-1; x++ {
		top.WriteString(paint(x, 0, g.h))
	}
	top.WriteString(paint(w-1, 0, g.tr))
	out := []string{top.String()}
	for i, line := range body {
		y := i + 1
		out = append(out, paint(0, y, g.v)+" "+Fit(line, w-4)+" "+paint(w-1, y, g.v))
	}
	var bot strings.Builder
	bot.WriteString(paint(0, h-1, g.bl))
	for x := 1; x < w-1; x++ {
		bot.WriteString(paint(x, h-1, g.h))
	}
	bot.WriteString(paint(w-1, h-1, g.br))
	return append(out, bot.String())
}

type glyphs struct{ tl, tr, bl, br, h, v string }

// Side places two blocks next to each other with a gap; a has width wa.
func Side(a []string, wa int, b []string, gap int) []string {
	n := max(len(a), len(b))
	out := make([]string, 0, n)
	for i := 0; i < n; i++ {
		l, r := "", ""
		if i < len(a) {
			l = a[i]
		}
		if i < len(b) {
			r = b[i]
		}
		out = append(out, Fit(l, wa)+strings.Repeat(" ", gap)+r)
	}
	return out
}

// Row is one selectable line, w cells wide. Not focused: two spaces, then styled. Focused: the ›
// marker in accent (the one light of the view), then plain in the selection style across the
// row, so the background never breaks on an inner style reset.
func Row(c Ctx, focused bool, styled, plain string, w int) string {
	if !focused {
		return "  " + Fit(styled, w-2)
	}
	return c.Th.B("accent", "› ") + c.Th.Selected().Render(Fit(plain, w-2))
}

// Next is the "Next time: <cmd>" line, the command wrapped to w with a hanging indent.
func Next(c Ctx, cmd string, w int) []string {
	label := c.T("next", "cmd", "")
	indent := Width(label)
	room := max(10, w-indent)
	var out []string
	for i := 0; len(cmd) > 0; i++ {
		part := cmd
		if len(part) > room {
			cut := strings.LastIndexAny(part[:room], " ,")
			if cut <= 0 {
				cut = room - 1
			}
			part = cmd[:cut+1]
		}
		cmd = cmd[len(part):]
		prefix := c.Th.R("fgMuted", label)
		if i > 0 {
			prefix = strings.Repeat(" ", indent)
		}
		out = append(out, prefix+c.Th.R("info", strings.TrimRight(part, " ")))
	}
	return out
}

// Words wraps plain text at spaces into lines of at most w cells.
func Words(text string, w int) []string {
	var out []string
	line := ""
	for _, word := range strings.Fields(text) {
		switch {
		case line == "":
			line = word
		case Width(line+" "+word) <= w:
			line += " " + word
		default:
			out = append(out, line)
			line = word
		}
	}
	return append(out, line)
}
