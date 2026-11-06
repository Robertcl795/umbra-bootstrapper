// Package effects is the only place where umbra-setup touches the world: environment, files,
// terminal, clock (Elm rule E4). Everything here reaches the program as a tea.Cmd that returns a
// typed message from internal/msgs. G3 has the read-only effects; running bootstrap.sh is G4.
package effects

import (
	"os"
	"os/user"
	"path/filepath"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/term"

	"github.com/Robertcl795/umbra-bootstrapper/internal/catalog"
	"github.com/Robertcl795/umbra-bootstrapper/internal/i18n"
	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
)

func readFile(p string) (string, bool) {
	b, err := os.ReadFile(p)
	if err != nil {
		return "", false
	}
	return string(b), true
}

// StdoutTTY reports whether stdout is a terminal.
func StdoutTTY() bool { return term.IsTerminal(os.Stdout.Fd()) }

// StdinTTY reports whether stdin is a terminal.
func StdinTTY() bool { return term.IsTerminal(os.Stdin.Fd()) }

// FromOS builds the Env from the real environment. envDir is the bootstrapper's env/wsl.
func FromOS(envDir, version string) sys.Env {
	get := os.Getenv
	p := theme.Detect(get, StdoutTTY())
	name, ok := theme.Variant(get("UM_THEME"), get("COLORFGBG"))
	e := sys.Env{
		Platform: sys.Platform(get, readFile),
		Root:     os.Geteuid() == 0,
		Desktop:  sys.DesktopSession(get),
		Access:   sys.AccessOverride(get),
		Terminal: sys.Terminal(get),
		Lang:     i18n.Resolve(get),
		Theme:    theme.New(name, p),
		NoMotion: sys.NoMotion(get, p),
		EnvDir:   envDir,
		Version:  version,
		Distro:   get("WSL_DISTRO_NAME"),
		ThemeSet: get("UM_THEME") != "",
		Driver:   get("UM_DRIVER"),
	}
	if !ok {
		e.ThemeBad = get("UM_THEME")
	}
	if u, err := user.Current(); err == nil {
		e.User = u.Username
	}
	return e
}

// EnvDir finds the bootstrapper's env/wsl: the flag, then UM_ENV_DIR, then next to the binary
// (<root>/build/umbra-setup), then the working directory, then where install.sh leaves the
// checkout (~/.local/share/umbra/bootstrapper, or ~/dev/umbra-bootstrapper after a WSL stage 1).
func EnvDir(flag string) string {
	for _, d := range []string{flag, os.Getenv("UM_ENV_DIR")} {
		if d != "" {
			return d
		}
	}
	var candidates []string
	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		candidates = append(candidates, filepath.Join(dir, "..", "env/wsl"), filepath.Join(dir, "env/wsl"))
	}
	candidates = append(candidates, filepath.FromSlash("env/wsl"))
	if home, err := os.UserHomeDir(); err == nil {
		candidates = append(candidates, filepath.Join(home, ".local/share/umbra/bootstrapper/env/wsl"),
			filepath.Join(home, "dev/umbra-bootstrapper/env/wsl"))
	}
	for _, d := range candidates {
		if _, err := os.Stat(filepath.Join(d, "install", "components.tsv")); err == nil {
			return filepath.Clean(d)
		}
	}
	return filepath.FromSlash("env/wsl")
}

// ReadCatalog reads components.tsv under envDir.
func ReadCatalog(envDir string) tea.Cmd {
	return func() tea.Msg {
		f, err := os.Open(filepath.Join(envDir, "install", "components.tsv"))
		if err != nil {
			return msgs.CatalogErr{Err: err.Error()}
		}
		defer f.Close()
		c, err := catalog.Parse(f)
		if err != nil {
			return msgs.CatalogErr{Err: err.Error()}
		}
		return msgs.Catalog{Cat: c}
	}
}

// Scan returns one command per fast scan fact, read from the Env; ScanSlow has the others.
func Scan(e sys.Env) []tea.Cmd {
	fact := func(f msgs.ScanFact) tea.Cmd { return func() tea.Msg { return f } }
	user := msgs.ScanFact{Key: "scan.user", Value: e.User, State: msgs.FactOK}
	if e.Root {
		user.ValueKey = "scan.root"
	}
	desktop := msgs.ScanFact{Key: "scan.desktop", ValueKey: "scan.desktop.none", State: msgs.FactNA}
	switch {
	case e.Desktop:
		desktop.ValueKey, desktop.State = "scan.desktop.yes", msgs.FactOK
	case strings.HasPrefix(e.Platform, "wsl-"):
		desktop.ValueKey = "scan.desktop.wsl"
	}
	return []tea.Cmd{
		fact(msgs.ScanFact{Key: "scan.platform", Value: e.Platform, State: okIf(e.Platform != "")}),
		fact(user),
		fact(desktop),
		fact(msgs.ScanFact{Key: "scan.terminal", Value: e.Terminal + " · " + profileName(e.Theme.Profile), State: msgs.FactOK}),
	}
}

func profileName(p theme.Profile) string {
	switch p {
	case theme.TrueColor:
		return "truecolor"
	case theme.ANSI16:
		return "ANSI-16"
	}
	return "NO_COLOR"
}

func okIf(b bool) msgs.FactState {
	if b {
		return msgs.FactOK
	}
	return msgs.FactBad
}

// ShineTick schedules the next corona sweep frame: frame 1, the start of a sweep, comes after the
// rest between sweeps (2.5 s); the others 50 ms apart (one sweep ≈ 1 s, ux-spec §6.3).
func ShineTick(frame int) tea.Cmd {
	d := 50 * time.Millisecond
	if frame == 1 {
		d = 2500 * time.Millisecond
	}
	return tea.Tick(d, func(time.Time) tea.Msg { return msgs.ShineTick{Frame: frame} })
}

// GlitchTick schedules the next glitch frame (≤ 600 ms in all, ux-spec §6.3).
func GlitchTick(frame int) tea.Cmd {
	return tea.Tick(200*time.Millisecond, func(time.Time) tea.Msg { return msgs.GlitchTick{Frame: frame} })
}
