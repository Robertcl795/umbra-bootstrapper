package app

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"

	"github.com/Robertcl795/umbra-bootstrapper/internal/catalog"
	"github.com/Robertcl795/umbra-bootstrapper/internal/effects"
	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/plan"
	"github.com/Robertcl795/umbra-bootstrapper/internal/screens"
	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
)

var update = flag.Bool("update", false, "rewrite testdata/golden")

func envDir() string { return filepath.Join("..", "..", "env", "wsl") }

func loadCat(t *testing.T) catalog.Catalog {
	t.Helper()
	msg := effects.ReadCatalog(envDir())()
	c, ok := msg.(msgs.Catalog)
	if !ok {
		t.Fatalf("catalog: %+v", msg)
	}
	return c.Cat
}

func fixtureEnv(variant string, p theme.Profile, lang string) sys.Env {
	yes := true
	return sys.Env{Platform: "wsl-arch", User: "rocker", Access: &yes, Terminal: "Windows Terminal",
		Lang: lang, Theme: theme.New(variant, p), NoMotion: true, EnvDir: envDir(), Version: "0.0.0-test"}
}

// started returns a model that has its size, facts and catalog, as after Init.
func started(t *testing.T, env sys.Env, w, h int) Model {
	t.Helper()
	var m tea.Model = New(env, Cmds{})
	m, _ = m.Update(tea.WindowSizeMsg{Width: w, Height: h})
	for _, c := range effects.Scan(env) {
		m, _ = m.Update(c())
	}
	m, _ = m.Update(msgs.Catalog{Cat: loadCat(t)})
	return m.(Model)
}

func key(k string) tea.KeyPressMsg {
	switch k {
	case "enter":
		return tea.KeyPressMsg{Code: tea.KeyEnter}
	case "esc":
		return tea.KeyPressMsg{Code: tea.KeyEscape}
	case "space":
		return tea.KeyPressMsg{Code: tea.KeySpace, Text: " "}
	case "up":
		return tea.KeyPressMsg{Code: tea.KeyUp}
	case "down":
		return tea.KeyPressMsg{Code: tea.KeyDown}
	case "left":
		return tea.KeyPressMsg{Code: tea.KeyLeft}
	case "right":
		return tea.KeyPressMsg{Code: tea.KeyRight}
	case "ctrl+c":
		return tea.KeyPressMsg{Code: 'c', Mod: tea.ModCtrl}
	}
	return tea.KeyPressMsg{Code: rune(k[0]), Text: k}
}

func press(m Model, keys ...string) (Model, tea.Cmd) {
	var tm tea.Model = m
	var cmd tea.Cmd
	for _, k := range keys {
		tm, cmd = tm.Update(key(k))
	}
	return tm.(Model), cmd
}

func TestKeyNamesMatchBubbleTea(t *testing.T) {
	for _, k := range []string{"enter", "esc", "space", "up", "down", "left", "right", "ctrl+c", "a", "n", "q"} {
		if got := key(k).String(); got != k {
			t.Errorf("key %q reads as %q", k, got)
		}
	}
}

// The TUI's result equals plan.Args for the same picks (contract C5/C6: one code path).
func TestFlowToInstallGivesPlanArgs(t *testing.T) {
	m := started(t, fixtureEnv("umbra", theme.TrueColor, "en"), 80, 24)
	m, _ = press(m, "enter")                                                   // boot → profile
	m, _ = press(m, "down", "enter")                                           // work → components
	m, _ = press(m, "space", "down", "down", "down", "down", "space", "enter") // untick packages and k8s
	m, _ = press(m, "right", "enter")                                          // void → review
	m, cmd := press(m, "enter")                                                // Install
	if cmd == nil {
		t.Fatal("Install did not quit")
	}
	res := m.Result()
	if res.Action != screens.Install {
		t.Fatalf("action %v", res.Action)
	}
	cat := loadCat(t)
	defaults := cat.Defaults("wsl-arch", false, true)
	want := slices.DeleteFunc(slices.Clone(defaults), func(id string) bool { return id == "packages" || id == "k8s" })
	args := plan.Args(cat, "wsl-arch", plan.Selection{Profile: "work", Items: want, Variant: "void"})
	if !slices.Equal(res.Args, args) {
		t.Errorf("TUI args\n %v\nwant\n %v", res.Args, args)
	}
}

func TestBackAndCancel(t *testing.T) {
	m := started(t, fixtureEnv("umbra", theme.TrueColor, "en"), 80, 24)
	m, _ = press(m, "enter", "enter", "esc")
	if m.screen != Profile {
		t.Errorf("esc from components: screen %d", m.screen)
	}
	m, cmd := press(m, "ctrl+c")
	if cmd == nil || m.Result().Action != screens.Quit {
		t.Errorf("ctrl+c: %+v", m.Result())
	}
}

func TestEmptySelectionCannotInstall(t *testing.T) {
	m := started(t, fixtureEnv("umbra", theme.TrueColor, "en"), 80, 24)
	m, _ = press(m, "enter", "enter", "n", "enter", "enter")
	if m.screen != Review || m.bcur != 2 {
		t.Fatalf("screen %d button %d", m.screen, m.bcur)
	}
	m, _ = press(m, "left")
	if m.bcur != 2 {
		t.Errorf("moved onto a disabled button: %d", m.bcur)
	}
	if !strings.Contains(m.Content(), "Select at least one component.") {
		t.Error("no empty-selection message")
	}
}

func TestThemeCursorRethemesTheScreen(t *testing.T) {
	m := started(t, fixtureEnv("umbra", theme.TrueColor, "en"), 80, 24)
	m, _ = press(m, "enter", "enter", "enter", "right", "right") // theme, cursor on lux
	if m.d.Sel.Variant != "lux" {
		t.Fatalf("variant %s", m.d.Sel.Variant)
	}
	fg := sgr(theme.Roles["lux"]["fg"])
	if !strings.Contains(m.Content(), fg) {
		t.Errorf("content not drawn in lux fg (%s)", fg)
	}
	if v := m.View(); v.BackgroundColor == nil {
		t.Error("truecolor view paints no background")
	}
}

func TestTooSmall(t *testing.T) {
	m := started(t, fixtureEnv("umbra", theme.None, "en"), 70, 20)
	if got := m.Content(); !strings.Contains(got, "Terminal is 70×20; umbra-setup needs 80×24.") {
		t.Errorf("small: %q", got)
	}
	var tm tea.Model = m
	tm, _ = tm.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	if !strings.Contains(tm.(Model).Content(), "SYSTEM SCAN") {
		t.Error("no redraw after resize")
	}
}

func TestUnsupportedPlatformBlocksBoot(t *testing.T) {
	env := fixtureEnv("umbra", theme.None, "en")
	env.Platform = ""
	m := started(t, env, 80, 24)
	m, _ = press(m, "enter")
	if m.screen != Boot || !strings.Contains(m.Content(), "unsupported system") {
		t.Errorf("screen %d", m.screen)
	}
}

func TestEveryViewIsExactlyTheTerminalSize(t *testing.T) {
	for _, size := range [][2]int{{80, 24}, {120, 32}} {
		m := started(t, fixtureEnv("umbra", theme.TrueColor, "en"), size[0], size[1])
		for s := Boot; s <= Review; s++ {
			lines := strings.Split(m.Content(), "\n")
			if len(lines) != size[1] {
				t.Errorf("%dx%d screen %d: %d lines", size[0], size[1], s, len(lines))
			}
			for i, l := range lines {
				if w := visibleWidth(l); w != size[0] {
					t.Errorf("%dx%d screen %d line %d: width %d", size[0], size[1], s, i, w)
				}
			}
			m, _ = press(m, "enter")
		}
	}
}

// ── golden View tests (ux-spec §8) ────────────────────────────────────────────

var profiles = map[string]theme.Profile{"true": theme.TrueColor, "ansi16": theme.ANSI16, "none": theme.None}

func screensOf(t *testing.T, env sys.Env, w, h int) map[string]string {
	m := started(t, env, w, h)
	out := map[string]string{}
	names := []string{"boot", "profile", "components", "theme", "review"}
	for _, n := range names {
		out[n] = m.Content()
		m, _ = press(m, "enter")
	}
	return out
}

func TestGolden(t *testing.T) {
	dir := filepath.Join("testdata", "golden")
	if *update {
		_ = os.MkdirAll(dir, 0o755)
	}
	check := func(name, got string) {
		p := filepath.Join(dir, name+".txt")
		if *update {
			if err := os.WriteFile(p, []byte(got), 0o644); err != nil {
				t.Fatal(err)
			}
			return
		}
		want, err := os.ReadFile(p)
		if err != nil {
			t.Fatalf("%s: %v (run go test ./internal/app -update)", p, err)
		}
		if string(want) != got {
			t.Errorf("%s differs (review it, then go test ./internal/app -update)", p)
		}
	}
	for _, v := range theme.Variants {
		for pn, p := range profiles {
			for s, content := range screensOf(t, fixtureEnv(v, p, "en"), 80, 24) {
				check(fmt.Sprintf("%s_%s_%s", s, v, pn), content)
			}
		}
	}
	for s, content := range screensOf(t, fixtureEnv("umbra", theme.None, "es"), 80, 24) {
		check("es_"+s, content)
	}
	for s, content := range screensOf(t, fixtureEnv("umbra", theme.TrueColor, "en"), 120, 32) {
		check("wide_"+s, content)
	}
}

// NO_COLOR output has no escape codes at all.
func TestNoColorHasNoEscapes(t *testing.T) {
	for s, content := range screensOf(t, fixtureEnv("umbra", theme.None, "en"), 80, 24) {
		if strings.Contains(content, "\x1b") {
			t.Errorf("%s: escape code with NO_COLOR", s)
		}
	}
}

// Proportion (ux-spec §6.4): accent and accent2 (and the gradient between them) cover at most
// 7 + 3 = 10% of the screen. Theme swatches show the palette itself and are not counted.
func TestAccentShare(t *testing.T) {
	for _, v := range theme.Variants {
		roles := theme.Roles[v]
		neutral := map[string]bool{}
		for _, r := range []string{"fg", "fgMuted", "border", "ok", "warn", "error", "info", "link"} {
			neutral[sgr(roles[r])] = true
		}
		for s, content := range screensOf(t, fixtureEnv(v, theme.TrueColor, "en"), 80, 24) {
			accent, _, _ := cells(content, neutral)
			share := 100 * float64(accent) / float64(80*24)
			t.Logf("%s %-10s accent %4.1f%% of the screen", v, s, share)
			if share > 10 {
				t.Errorf("%s %s: accent covers %.1f%% of the screen (> 10%%)", v, s, share)
			}
		}
	}
}

var sgrRe = regexp.MustCompile(`\x1b\[([0-9;]*)m`)

func sgr(hex string) string {
	r, _ := strconv.ParseUint(hex[1:3], 16, 8)
	g, _ := strconv.ParseUint(hex[3:5], 16, 8)
	b, _ := strconv.ParseUint(hex[5:7], 16, 8)
	return fmt.Sprintf("38;2;%d;%d;%d", r, g, b)
}

// cells counts non-space cells: in an accent color (not neutral), how many of those are heavy
// border glyphs, and all drawn.
func cells(content string, neutral map[string]bool) (accent, border, drawn int) {
	for _, line := range strings.Split(content, "\n") {
		fg := ""
		rest := line
		for len(rest) > 0 {
			loc := sgrRe.FindStringSubmatchIndex(rest)
			text := rest
			if loc != nil {
				text = rest[:loc[0]]
			}
			for _, r := range text {
				if r == ' ' || r == '█' {
					continue
				}
				drawn++
				if fg != "" && !neutral[fg] {
					accent++
					if strings.ContainsRune("┏┓┗┛━┃", r) {
						border++
					}
				}
			}
			if loc == nil {
				break
			}
			params := rest[loc[2]:loc[3]]
			switch {
			case params == "" || params == "0" || params == "39":
				fg = ""
			case strings.Contains(params, "38;2;"):
				i := strings.Index(params, "38;2;")
				p := strings.Split(params[i:], ";")
				if len(p) >= 5 {
					fg = strings.Join(p[:5], ";")
				}
			}
			rest = rest[loc[1]:]
		}
	}
	return accent, border, drawn
}

func visibleWidth(s string) int {
	return len([]rune(sgrRe.ReplaceAllString(s, "")))
}
