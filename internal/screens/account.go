package screens

import (
	"strings"

	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
	"github.com/Robertcl795/umbra-bootstrapper/internal/ui"
)

// Account is the user stage 1 creates (or sets up) on a fresh WSL distro, asked only as root:
// stage 1 runs without a terminal under umbra-setup, so it cannot ask itself (stage1.sh p2_pre).
type Account struct {
	User, Pass, Again string
	Field             int    // 0 user, 1 password, 2 again
	Err               string // i18n key of the last validation error
}

// AccountFor starts the screen: an existing regular user is named, as stage 1 would require.
func AccountFor(existing []string) Account {
	a := Account{}
	if len(existing) > 0 {
		a.User = existing[0]
	}
	return a
}

// AccountView asks for the user and a password (masked; never drawn).
func AccountView(c ui.Ctx, a Account, existing []string) []string {
	w := bodyW(c) - 4
	intro := c.T("account.new")
	if len(existing) > 0 {
		intro = c.T("account.existing", "users", strings.Join(existing, ", "))
	}
	field := func(i int, label, value string) string {
		box := c.Th.R("fgMuted", ui.Fit(label, 18))
		v := value + strings.Repeat(" ", max(0, 25-ui.Width(value)))
		if i == a.Field { // the terminal's cursor sits after the text (AccountCursor)
			return c.Th.B("accent", "› ") + box + c.Th.Selected().Render(v)
		}
		return "  " + box + c.Th.R("fg", v)
	}
	lines := []string{c.Th.B("fg", c.T("account.ask")), ""}
	for _, l := range ui.Words(intro, w) {
		lines = append(lines, c.Th.R("fgMuted", l))
	}
	lines = append(lines, "",
		field(0, c.T("account.user"), a.User),
		field(1, c.T("account.pass"), strings.Repeat("•", len([]rune(a.Pass)))),
		field(2, c.T("account.again"), strings.Repeat("•", len([]rune(a.Again)))), "")
	if a.Err != "" {
		lines = append(lines, c.Th.R("error", "! "+c.T(a.Err)))
	} else {
		for _, l := range ui.Words(c.T("account.help"), w) {
			lines = append(lines, c.Th.R("fgMuted", l))
		}
	}
	return append([]string{""}, ui.Panel(c, c.T("account.title"), lines, bodyW(c), 0, false)...)
}

// AccountCursor is where the terminal's cursor goes on the focused field's row: the field's
// label as the row shows it (the row is found by it) and the cells from the marker to the cursor.
func AccountCursor(c ui.Ctx, a Account) (label string, x int) {
	values := []string{a.User, strings.Repeat("•", len([]rune(a.Pass))), strings.Repeat("•", len([]rune(a.Again)))}
	label = ui.Fit(c.T([]string{"account.user", "account.pass", "account.again"}[a.Field]), 18)
	return "› " + label, 2 + 18 + ui.Width(values[a.Field])
}

// AccountKeys lists the footer keys of account.
func AccountKeys(c ui.Ctx) []ui.Key {
	return []ui.Key{{Key: "tab", Desc: c.T("key.nextfield")}, {Key: "enter", Desc: c.T("key.next")}, {Key: "esc", Desc: c.T("key.back")}}
}

// AccountKey edits the focused field; enter on the last field checks all three.
func AccountKey(key string, a Account) (Account, Action) {
	a.Err = ""
	get := func() *string { return []*string{&a.User, &a.Pass, &a.Again}[a.Field] }
	switch key {
	case "tab", "down":
		a.Field = (a.Field + 1) % 3
	case "shift+tab", "up":
		a.Field = (a.Field + 2) % 3
	case "esc":
		return a, Back
	case "backspace":
		if r := []rune(*get()); len(r) > 0 {
			*get() = string(r[:len(r)-1])
		}
	case "enter":
		if a.Field < 2 {
			a.Field++
			return a, None
		}
		switch {
		case !sys.ValidUsername(a.User):
			a.Err, a.Field = "account.bad.user", 0
		case a.Pass == "":
			a.Err, a.Field = "account.bad.empty", 1
		case a.Pass != a.Again:
			a.Err, a.Field, a.Again = "account.bad.match", 2, ""
		default:
			return a, Next
		}
	default:
		text := key
		if key == "space" {
			text = " "
		}
		if len([]rune(text)) == 1 && (a.Field > 0 || text != " ") {
			*get() += text
		}
	}
	return a, None
}
