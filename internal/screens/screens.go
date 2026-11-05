// Package screens draws each screen of umbra-setup and turns its keys into actions (ux-spec §3).
// Views are pure functions of their data (Elm rule E2); key handlers are pure functions that
// return the new screen state and an Action for the app (E1). Nothing here does I/O (E4).
package screens

import (
	"slices"
	"strings"

	"github.com/Robertcl795/umbra-bootstrapper/internal/catalog"
	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/plan"
	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
	"github.com/Robertcl795/umbra-bootstrapper/internal/ui"
)

// Action is what a key asks the app to do.
type Action int

const (
	None Action = iota
	Next
	Back
	Quit
	Install
	DryRun
)

// Data is what the screens read. The app owns it.
type Data struct {
	Env    sys.Env
	Cat    catalog.Catalog
	Items  []catalog.Item // offered on Env.Platform, menu order
	Facts  []msgs.ScanFact
	Ready  bool // the catalog is in
	CatErr string
	Sel    Selection

	Installed    map[string]bool // items a previous run installed (re-run); cannot be unticked
	Passwordless bool            // sudo needs no password now (or root)
	SudoErr      string          // the last sudo -v failure, shown on review
	Spin         int             // spinner frame
	Extra        []string        // arguments the app adds (--user for stage 1)
}

// Selection is what the user picked so far.
type Selection struct {
	Profile string // personal or work
	Chosen  map[string]bool
	Variant string
}

// Plan returns the plan.Selection for the current picks, in menu order.
func (d Data) Plan() plan.Selection {
	var ids []string
	for _, it := range d.Items {
		if d.Sel.Chosen[it.ID] {
			ids = append(ids, it.ID)
		}
	}
	return plan.Selection{Profile: d.Sel.Profile, Items: ids, Variant: d.Sel.Variant}
}

// Args are the install.sh arguments for the current picks, plus Extra.
func (d Data) Args() []string { return append(plan.Args(d.Cat, d.Env.Platform, d.Plan()), d.Extra...) }

func bodyW(c ui.Ctx) int { return c.W - 2 }

func kv(c ui.Ctx, key, value string, role string, w int) string {
	return c.Th.R("fgMuted", ui.Fit(key, w)) + c.Th.R(role, value)
}

// ── boot ─────────────────────────────────────────────────────────────────────

var wordmark = []string{"█ █ █▀▄▀█ █▄▄ █▀█ ▄▀█", "█▄█ █ ▀ █ █▄█ █▀▄ █▀█"}

// BootView is the wordmark, the tagline and the system scan. glitch is the frame (0 = still).
func BootView(c ui.Ctx, d Data, glitch int) []string {
	var out []string
	for _, line := range wordmark {
		switch glitch {
		case 1:
			out = append(out, " "+c.Th.R("info", " "+line))
		case 2:
			out = append(out, c.Th.R("accent2", line))
		default:
			out = append(out, " "+c.Th.B("fg", line))
		}
	}
	out = append(out, " "+c.Th.R("fgMuted", c.T("boot.tagline")), "")
	var lines []string
	for _, f := range d.Facts {
		badge := map[msgs.FactState][2]string{
			msgs.FactOK: {"ok", "[ OK ]"}, msgs.FactNA: {"fgMuted", "[ -- ]"},
			msgs.FactPending: {"info", "[ " + spinner[d.Spin%len(spinner)] + "  ]"}, msgs.FactBad: {"error", "[ !! ]"},
		}[f.State]
		val := f.Value
		if f.ValueKey != "" {
			if val != "" {
				val += " · "
			}
			val += c.T(f.ValueKey)
		}
		valRole := "fg"
		if f.State == msgs.FactNA {
			valRole = "fgMuted"
		}
		lines = append(lines, c.Th.R(badge[0], badge[1])+" "+c.Th.B("fg", ui.Fit(c.T(f.Key), 12))+c.Th.R(valRole, val))
	}
	out = append(out, ui.Panel(c, c.T("boot.scan"), lines, bodyW(c), 5, false)...)
	out = append(out, "")
	switch {
	case d.Env.Platform == "":
		out = append(out, c.Th.R("error", "! "+c.T("err.platform")))
	case d.CatErr != "":
		out = append(out, c.Th.R("error", "! "+c.T("err.catalog", "err", d.CatErr)))
	case rootOutsideWSL(d):
		out = append(out, c.Th.R("error", "! "+c.T("err.root")))
	default:
		out = append(out, c.Th.R("fgMuted", c.T("boot.readonly")))
	}
	if d.Env.ThemeBad != "" {
		out = append(out, c.Th.R("warn", "! "+c.T("err.theme", "v", d.Env.ThemeBad)))
	}
	return out
}

// BootKeys lists the footer keys of boot.
func BootKeys(c ui.Ctx, d Data) []ui.Key {
	if !BootCanContinue(d) {
		return []ui.Key{{Key: "q", Desc: c.T("key.quit")}}
	}
	return []ui.Key{{Key: "enter", Desc: c.T("key.continue")}, {Key: "q", Desc: c.T("key.quit")}}
}

// BootCanContinue: the platform is supported, the catalog is in and no scan line is pending
// (the Umbra AI access decides which items are offered).
func BootCanContinue(d Data) bool {
	for _, f := range d.Facts {
		if f.State == msgs.FactPending {
			return false
		}
	}
	return d.Env.Platform != "" && d.Ready && d.CatErr == "" && !rootOutsideWSL(d)
}

// rootOutsideWSL: bootstrap.sh refuses root unless it is a WSL distro's stage 1.
func rootOutsideWSL(d Data) bool { return d.Env.Root && !strings.HasPrefix(d.Env.Platform, "wsl-") }

// BootKey handles a key on boot.
func BootKey(key string, d Data) Action {
	switch key {
	case "enter":
		if BootCanContinue(d) {
			return Next
		}
	case "q", "esc":
		return Quit
	}
	return None
}

// ── profile ──────────────────────────────────────────────────────────────────

// Profiles in menu order.
var Profiles = []string{"personal", "work"}

// ProfileView asks for the profile; cursor is the focused option.
func ProfileView(c ui.Ctx, d Data, cursor int) []string {
	w := bodyW(c) - 4
	lines := []string{c.Th.B("fg", c.T("profile.ask")), ""}
	for i, p := range Profiles {
		radio := "○ "
		if d.Sel.Profile == p {
			radio = "● "
		}
		desc := c.T("profile." + p)
		lines = append(lines,
			ui.Row(c, i == cursor, c.Th.R("fg", radio)+c.Th.B("fg", ui.Fit(p, 10))+c.Th.R("fg", desc), radio+ui.Fit(p, 10)+desc, w),
			strings.Repeat(" ", 14)+c.Th.R("fgMuted", c.T("profile."+p+".more")), "")
	}
	if Profiles[cursor] == "work" {
		lines = append(lines, c.Th.R("warn", "! ")+c.Th.R("fgMuted", c.T("profile.work.warn")))
	} else {
		lines = append(lines, "")
	}
	lines = append(lines, "")
	lines = append(lines, ui.Next(c, "install.sh --profile "+Profiles[cursor], w)...)
	return append([]string{""}, ui.Panel(c, c.T("profile.title"), lines, bodyW(c), 0, false)...)
}

// ProfileKeys lists the footer keys of profile.
func ProfileKeys(c ui.Ctx) []ui.Key {
	return []ui.Key{{Key: "↑↓", Desc: c.T("key.move")}, {Key: "enter", Desc: c.T("key.choose")}, {Key: "esc", Desc: c.T("key.back")}, {Key: "q", Desc: c.T("key.quit")}}
}

// ProfileKey moves the cursor or chooses.
func ProfileKey(key string, cursor int) (int, Action) {
	switch key {
	case "up", "k":
		return (cursor + len(Profiles) - 1) % len(Profiles), None
	case "down", "j":
		return (cursor + 1) % len(Profiles), None
	case "enter", "space":
		return cursor, Next
	case "esc":
		return cursor, Back
	case "q":
		return cursor, Quit
	}
	return cursor, None
}

// ── components ───────────────────────────────────────────────────────────────

// ComponentsView is the list (focused) and the detail of the item under the cursor.
func ComponentsView(c ui.Ctx, d Data, cursor int) []string {
	bw := bodyW(c)
	lw := bw/2 + 1
	rw := bw - lw - 1
	var left []string
	n := 0
	for i, it := range d.Items {
		box := "[ ] "
		role := "fgMuted"
		if d.Sel.Chosen[it.ID] {
			box, role = "[■] ", "fg"
			n++
		}
		label := it.Label[d.Env.Lang]
		styled := c.Th.R(role, box+label)
		if d.Installed[it.ID] {
			tag := " · " + c.T("comp.installed")
			label += tag
			styled += c.Th.R("fgMuted", tag)
		}
		left = append(left, ui.Row(c, i == cursor, styled, box+label, lw-4))
	}
	left = append(left, "", c.Th.R("fgMuted", c.T("comp.count", "n", itoa(n), "total", itoa(len(d.Items)))))
	var right []string
	if cursor < len(d.Items) {
		it := d.Items[cursor]
		dash := func(s string) string {
			if s == "" {
				return "—"
			}
			return s
		}
		kw := 11
		right = []string{
			c.Th.B("fg", strings.ToUpper(it.ID)),
			c.Th.R("fg", it.Summary[d.Env.Lang]),
			"",
			kv(c, c.T("comp.installs"), dash(it.Installs), "fg", kw),
			kv(c, c.T("comp.deploys"), dash(it.Deploys), "info", kw),
			kv(c, c.T("comp.phase"), scriptsName(it.Scripts), "fg", kw),
			kv(c, c.T("comp.check"), dash(it.Check), "fg", kw),
			kv(c, c.T("comp.work"), c.T("comp.work."+it.Work), map[bool]string{true: "warn", false: "fg"}[it.Work != "same"], kw),
			"",
			kv(c, c.T("comp.add"), "--components "+strings.Join(it.Components, ","), "link", kw),
			kv(c, c.T("comp.skip"), "--skip "+strings.Join(it.Components, ","), "link", kw),
		}
	}
	h := max(len(left), len(right))
	return append([]string{""}, ui.Side(ui.Panel(c, c.T("comp.title"), left, lw, h, true), lw,
		ui.Panel(c, c.T("comp.detail"), right, rw, h, false), 1)...)
}

func scriptsName(scripts []string) string {
	if len(scripts) == 0 {
		return "—"
	}
	s := strings.TrimSuffix(strings.TrimPrefix(strings.TrimPrefix(scripts[0], "run_onchange_"), "run_once_"), ".sh")
	if len(scripts) > 1 {
		s += " +" + itoa(len(scripts)-1)
	}
	return s
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}

// ComponentsKeys lists the footer keys of components.
func ComponentsKeys(c ui.Ctx) []ui.Key {
	return []ui.Key{{Key: "↑↓", Desc: c.T("key.move")}, {Key: "space", Desc: c.T("key.toggle")}, {Key: "a", Desc: c.T("key.all")},
		{Key: "n", Desc: c.T("key.none")}, {Key: "enter", Desc: c.T("key.next")}, {Key: "esc", Desc: c.T("key.back")}}
}

// ComponentsKey moves, toggles or leaves. chosen is changed in a copy.
func ComponentsKey(key string, cursor int, d Data) (int, map[string]bool, Action) {
	chosen := map[string]bool{}
	for k, v := range d.Sel.Chosen {
		chosen[k] = v
	}
	n := len(d.Items)
	switch key {
	case "up", "k":
		return (cursor + n - 1) % max(n, 1), chosen, None
	case "down", "j":
		return (cursor + 1) % max(n, 1), chosen, None
	case "space":
		if cursor < n && !d.Installed[d.Items[cursor].ID] {
			id := d.Items[cursor].ID
			chosen[id] = !chosen[id]
		}
	case "a":
		for _, it := range d.Items {
			chosen[it.ID] = true
		}
	case "n":
		chosen = map[string]bool{}
		for id := range d.Installed {
			chosen[id] = true
		}
	case "enter":
		return cursor, chosen, Next
	case "esc":
		return cursor, chosen, Back
	case "q":
		return cursor, chosen, Quit
	}
	return cursor, chosen, None
}

// ── theme ────────────────────────────────────────────────────────────────────

var swatchRows = [][]string{{"bgDeep", "bg", "surface", "border", "fgMuted", "fg"}, {"accent", "accent2", "info", "warn", "ok", "error"}}

// ThemeView shows the three variants; the app draws the whole screen in the one under cursor.
func ThemeView(c ui.Ctx, cursor int) []string {
	bw := bodyW(c)
	cw := (bw - 2) / 3
	var cards [][]string
	for i, v := range theme.Variants {
		lines := []string{c.Th.R("fgMuted", c.T("theme."+v)), ""}
		for _, roles := range swatchRows {
			var b strings.Builder
			for _, r := range roles {
				b.WriteString(c.Th.Swatch(v, r) + " ")
			}
			lines = append(lines, b.String())
		}
		vt := c.Th.With(v)
		lines = append(lines, "", vt.R("accent2", "❯ ")+vt.R("info", "~/dev ")+vt.R("accent", "main ")+vt.R("ok", "✓"))
		cards = append(cards, ui.Panel(c, strings.ToUpper(v), lines, cw, 0, i == cursor))
	}
	row := ui.Side(ui.Side(cards[0], cw, cards[1], 1), 2*cw+1, cards[2], 1)
	out := []string{"", c.Th.B("fg", c.T("theme.ask")), ""}
	out = append(out, row...)
	out = append(out, "", c.Th.R("fgMuted", c.T("theme.follows")), c.Th.R("fgMuted", c.T("theme.others")), "")
	return append(out, ui.Next(c, "UM_THEME="+theme.Variants[cursor]+" chezmoi init --apply", bw)...)
}

// ThemeKeys lists the footer keys of theme.
func ThemeKeys(c ui.Ctx) []ui.Key {
	return []ui.Key{{Key: "←→", Desc: c.T("key.move")}, {Key: "enter", Desc: c.T("key.choose")}, {Key: "esc", Desc: c.T("key.back")}}
}

// ThemeKey moves the cursor (the app re-themes on every move) or chooses.
func ThemeKey(key string, cursor int) (int, Action) {
	n := len(theme.Variants)
	switch key {
	case "left", "up", "h", "k":
		return (cursor + n - 1) % n, None
	case "right", "down", "l", "j", "tab":
		return (cursor + 1) % n, None
	case "enter", "space":
		return cursor, Next
	case "esc":
		return cursor, Back
	case "q":
		return cursor, Quit
	}
	return cursor, None
}

// ── review ───────────────────────────────────────────────────────────────────

// Buttons of review, in order.
var Buttons = []string{"btn.install", "btn.dry", "btn.back"}

// ReviewView is the plan, the equivalent command and the buttons.
func ReviewView(c ui.Ctx, d Data, button int) []string {
	bw := bodyW(c)
	w := bw - 4
	p := d.Plan()
	var skipped []string
	for _, it := range d.Items {
		if !d.Sel.Chosen[it.ID] {
			skipped = append(skipped, it.ID)
		}
	}
	kw := 11
	skip := strings.Join(skipped, " · ")
	skipRole := "fg"
	if skip == "" {
		skip, skipRole = c.T("review.nothing"), "fgMuted"
	}
	sudo := c.T("review.sudo.once")
	switch {
	case d.Env.Root:
		sudo = c.T("review.sudo.root")
	case d.Passwordless:
		sudo = c.T("review.sudo.free")
	}
	lines := []string{
		kv(c, c.T("review.platform"), d.Env.Platform, "fg", kw),
		kv(c, c.T("review.profile"), p.Profile, "fg", kw),
		kv(c, c.T("review.theme"), p.Variant, "fg", kw),
	}
	for i, part := range wrap(p.Items, " · ", w-kw) {
		k := ""
		if i == 0 {
			k = c.T("review.install")
		}
		lines = append(lines, kv(c, k, part, "fg", kw))
	}
	lines = append(lines,
		kv(c, c.T("review.skip"), skip, skipRole, kw),
		kv(c, c.T("review.sudo"), sudo, "fg", kw),
		kv(c, c.T("review.rerun"), c.T("review.rerun.safe"), "fgMuted", kw),
		"",
	)
	if d.SudoErr != "" {
		lines = append(lines, c.Th.R("error", "! "+c.T("review.sudo.failed", "err", d.SudoErr)))
	}
	if len(p.Items) == 0 {
		lines = append(lines, c.Th.R("error", "! "+c.T("review.empty")))
	} else {
		lines = append(lines, ui.Next(c, plan.Command(d.Args()), w)...)
	}
	lines = append(lines, "")
	var row strings.Builder
	for i, b := range Buttons {
		label := "[ " + c.T(b) + " ]"
		disabled := len(p.Items) == 0 && i < 2
		switch {
		case i == button:
			row.WriteString(c.Th.B("accent", "› ") + c.Th.Selected().Bold(c.Th.Profile != theme.None).Render(label))
		case disabled:
			row.WriteString("  " + c.Th.R("fgMuted", label))
		default:
			row.WriteString("  " + c.Th.R("fg", label))
		}
		row.WriteString(" ")
	}
	lines = append(lines, row.String())
	return append([]string{""}, ui.Panel(c, c.T("review.title"), lines, bw, 0, false)...)
}

// wrap joins items with sep into lines of at most w cells.
func wrap(items []string, sep string, w int) []string {
	var out []string
	line := ""
	for _, it := range items {
		switch {
		case line == "":
			line = it
		case ui.Width(line+sep+it) <= w:
			line += sep + it
		default:
			out = append(out, line)
			line = it
		}
	}
	if line != "" || len(out) == 0 {
		out = append(out, line)
	}
	return out
}

// ReviewKeys lists the footer keys of review.
func ReviewKeys(c ui.Ctx) []ui.Key {
	return []ui.Key{{Key: "←→", Desc: c.T("key.move")}, {Key: "enter", Desc: c.T("key.confirm")}, {Key: "esc", Desc: c.T("key.back")}, {Key: "q", Desc: c.T("key.quit")}}
}

// ReviewKey moves between buttons or presses one. Install and Dry run are disabled with an
// empty selection.
func ReviewKey(key string, button int, d Data) (int, Action) {
	empty := len(d.Plan().Items) == 0
	n := len(Buttons)
	move := func(step int) int {
		b := button
		for range n {
			b = (b + step + n) % n
			if !empty || b == 2 {
				return b
			}
		}
		return button
	}
	switch key {
	case "left", "h", "shift+tab":
		return move(-1), None
	case "right", "l", "tab":
		return move(1), None
	case "enter", "space":
		switch {
		case button == 2:
			return button, Back
		case empty:
			return button, None
		case button == 0:
			return button, Install
		default:
			return button, DryRun
		}
	case "esc":
		return button, Back
	case "q":
		return button, Quit
	}
	return button, None
}

// ReviewStart is the button focused when review opens.
func ReviewStart(d Data) int {
	if len(d.Plan().Items) == 0 {
		return 2
	}
	return 0
}

// ── too small ────────────────────────────────────────────────────────────────

// SmallView says the terminal is too small; it draws without the frame.
func SmallView(c ui.Ctx) string {
	msg := c.T("small", "w", itoa(c.W), "h", itoa(c.H))
	return c.Th.R("warn", "! ") + c.Th.R("fg", msg)
}

// Defaults returns the first Selection for a platform: catalog defaults, personal, the
// detected variant.
func Defaults(d Data) Selection {
	access := d.Env.Access != nil && *d.Env.Access
	chosen := map[string]bool{}
	for _, id := range d.Cat.Defaults(d.Env.Platform, d.Env.Desktop, access) {
		chosen[id] = true
	}
	return Selection{Profile: "personal", Chosen: chosen, Variant: d.Env.Theme.Name}
}

// Offered keeps the items the user may see: Umbra AI needs access (as selector_defaults in selector.sh).
func Offered(cat catalog.Catalog, e sys.Env) []catalog.Item {
	access := e.Access != nil && *e.Access
	items := cat.For(e.Platform)
	return slices.DeleteFunc(items, func(it catalog.Item) bool { return it.Default == "ai-access" && !access })
}
