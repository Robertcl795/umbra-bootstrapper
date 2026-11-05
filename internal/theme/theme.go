// Package theme turns the role tokens into terminal styles (setup-tui ux-spec §6). Colors come
// only from tokens_gen.go (generated); this file names roles, ANSI slots and gradients.
// It is the same model as um's internal/theme (ADR 0037: shared by generation, not by import).
package theme

import (
	"image/color"
	"strings"

	"charm.land/lipgloss/v2"
	"github.com/charmbracelet/x/ansi"
)

// Profile is how colors are written.
type Profile int

const (
	None      Profile = iota // NO_COLOR, no TTY or TERM=dumb: no escape codes at all
	ANSI16                   // the explicit slot map below
	TrueColor                // the role's hex value for the variant
)

// Detect picks the profile: none when NO_COLOR is non-empty, stdout is not a TTY or TERM is
// dumb; truecolor when COLORTERM is truecolor/24bit or WT_SESSION is set (Windows Terminal,
// verify); ANSI-16 otherwise.
func Detect(get func(string) string, stdoutTTY bool) Profile {
	if get("NO_COLOR") != "" || !stdoutTTY || get("TERM") == "dumb" {
		return None
	}
	switch strings.ToLower(get("COLORTERM")) {
	case "truecolor", "24bit":
		return TrueColor
	}
	if get("WT_SESSION") != "" {
		return TrueColor
	}
	return ANSI16
}

// Variants in the order the theme screen shows them.
var Variants = []string{"umbra", "void", "lux"}

// Variant resolves the theme: UM_THEME, else COLORFGBG ("fg;bg", bg 7 or 15 = light → lux),
// else umbra. ok is false when UM_THEME holds an unknown value.
func Variant(umTheme, colorfgbg string) (name string, ok bool) {
	if umTheme != "" {
		if _, known := Roles[umTheme]; known {
			return umTheme, true
		}
		return "umbra", false
	}
	if i := strings.LastIndex(colorfgbg, ";"); i >= 0 {
		if bg := colorfgbg[i+1:]; bg == "7" || bg == "15" {
			return "lux", true
		}
	}
	return "umbra", true
}

// slot is the ANSI-16 fallback of each role (um ux-spec §5.2; border: bright black).
var slot = map[string]int{"fgMuted": 7, "accent": 4, "accent2": 5, "info": 6, "warn": 3, "ok": 2, "error": 1, "link": 4, "border": 8}

// T is a resolved theme.
type T struct {
	Name    string
	Profile Profile
}

// New returns the theme for a variant and profile.
func New(name string, p Profile) T { return T{Name: name, Profile: p} }

// With returns the same profile in another variant (the theme screen's live preview).
func (t T) With(name string) T { return T{Name: name, Profile: t.Profile} }

// Hex is the role's value for this variant.
func (t T) Hex(role string) string { return Roles[t.Name][role] }

// Color returns the color of a role, or nil when the role draws in the terminal default.
func (t T) Color(role string) color.Color {
	switch t.Profile {
	case TrueColor:
		return lipgloss.Color(Roles[t.Name][role])
	case ANSI16:
		if n, ok := slot[role]; ok {
			return ansi.BasicColor(n)
		}
	}
	return nil
}

// Style returns a lipgloss style for a role. With Profile None it is empty.
func (t T) Style(role string) lipgloss.Style {
	s := lipgloss.NewStyle()
	if t.Profile == None {
		return s
	}
	if c := t.Color(role); c != nil {
		s = s.Foreground(c)
	}
	if role == "accent" && t.Profile == ANSI16 {
		s = s.Bold(true)
	}
	return s
}

// Bold is the role's style in bold (plain without color).
func (t T) Bold(role string) lipgloss.Style {
	if t.Profile == None {
		return lipgloss.NewStyle()
	}
	return t.Style(role).Bold(true)
}

// R renders s in a role.
func (t T) R(role, s string) string { return t.Style(role).Render(s) }

// B renders s in a role, bold.
func (t T) B(role, s string) string { return t.Bold(role).Render(s) }

// Selected is the selected-row style: selection background with fg; reverse video in ANSI-16;
// nothing without color (the › marker is the cue).
func (t T) Selected() lipgloss.Style {
	switch t.Profile {
	case TrueColor:
		return lipgloss.NewStyle().Background(lipgloss.Color(t.Hex("selection"))).Foreground(lipgloss.Color(t.Hex("fg")))
	case ANSI16:
		return lipgloss.NewStyle().Reverse(true)
	}
	return lipgloss.NewStyle()
}

// Background is the color the view paints behind everything (truecolor only).
func (t T) Background() color.Color {
	if t.Profile != TrueColor {
		return nil
	}
	return lipgloss.Color(t.Hex("bg"))
}

// dark reports whether the variant uses the map's (dark) gradient stops.
func (t T) dark() bool { return t.Name != "lux" }

// stops returns the gradient stops: the map's values in dark variants; in lux, the variant's
// own roles (ux-spec §6.2: the map's stops are dark values).
func (t T) stops(name string) []color.Color {
	var hexes []string
	switch {
	case t.dark():
		hexes = Gradients[name]
	case name == "corona":
		hexes = []string{t.Hex("accent"), t.Hex("accent2"), t.Hex("warn")}
	default:
		hexes = []string{t.Hex("accent"), t.Hex("accent2")}
	}
	out := make([]color.Color, len(hexes))
	for i, h := range hexes {
		out[i] = lipgloss.Color(h)
	}
	return out
}

// BorderGrid returns one color per cell of a w×h box for the focused border, row-major,
// following gradient.activeBorder at its angle. Without truecolor it returns nil (callers use
// the accent role instead).
func (t T) BorderGrid(w, h int) []color.Color {
	if t.Profile != TrueColor {
		return nil
	}
	return lipgloss.Blend2D(w, h, float64(ActiveBorderAngle), t.stops("activeBorder")...)
}

// Corona returns n colors along gradient.corona (the progress bar); nil without truecolor.
func (t T) Corona(n int) []color.Color {
	if t.Profile != TrueColor || n < 1 {
		return nil
	}
	return lipgloss.Blend1D(n, t.stops("corona")...)
}

// Swatch renders "██" in a role of another variant (the theme screen's cards).
func (t T) Swatch(variant, role string) string {
	return t.With(variant).R(role, "██")
}
