package app

import (
	"strings"
	"testing"

	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
)

// atShell is the Shell screen on wsl-arch: boot → profile → components → shell.
func atShell(t *testing.T) Model {
	t.Helper()
	m := started(t, fixtureEnv("umbra", theme.None, "en"), 80, 24)
	m, _ = press(m, "enter", "enter", "enter")
	if m.screen != Shell {
		t.Fatalf("screen %d, want Shell", m.screen)
	}
	return m
}

// The shell items live on their own screen, not in Components (plan installer-packages-shell, R4).
func TestShellItemsAreNotInComponents(t *testing.T) {
	m := atComponents(t)
	for _, s := range []string{"Shell: zsh", "PowerShell 7"} {
		if strings.Contains(m.Content(), s) {
			t.Errorf("components lists %q", s)
		}
	}
}

// Zsh is the default; picking Fish passes --shell fish; the detail lists fish's packages.
func TestShellScreenPicksFish(t *testing.T) {
	m := atShell(t)
	if m.Title() != "Umbra setup · shell zsh" {
		t.Fatalf("title %q", m.Title())
	}
	if !strings.Contains(strings.Join(m.d.Args(), " "), "--shell zsh") {
		t.Errorf("default args %v", m.d.Args())
	}
	m, _ = press(m, "down")
	if !strings.Contains(m.Content(), "fzf.fish: ") {
		t.Error("the fish detail does not list fzf.fish")
	}
	m, _ = press(m, "space")
	if args := strings.Join(m.d.Args(), " "); !strings.Contains(args, "--shell fish") {
		t.Errorf("args %s", args)
	}
	m, _ = press(m, "enter")
	if m.screen != Theme {
		t.Errorf("enter: screen %d, want Theme", m.screen)
	}
}

// On WSL, "Update to PowerShell 7" adds the pwsh7 component; it is off by default.
func TestShellScreenOffersPowerShell7OnWSL(t *testing.T) {
	m := atShell(t)
	if !strings.Contains(m.Content(), "Update to PowerShell 7") {
		t.Fatal("no PowerShell 7 row on WSL")
	}
	if strings.Contains(strings.Join(m.d.Args(), " "), "pwsh7") {
		t.Error("pwsh7 is on by default")
	}
	m, _ = press(m, "down", "down", "down", "space") // zsh, fish, no shell setup, PowerShell 7
	if args := strings.Join(m.d.Args(), " "); !strings.Contains(args, ",pwsh7") {
		t.Errorf("args %s", args)
	}
	n := started(t, nativeEnv(), 80, 24)
	n, _ = press(n, "enter", "enter", "enter")
	if n.screen != Shell || strings.Contains(n.Content(), "PowerShell 7") {
		t.Errorf("native Arch: screen %d, PowerShell 7 offered", n.screen)
	}
}

// A re-run starts from the stored shell.
func TestRerunKeepsTheStoredShell(t *testing.T) {
	m := send(started(t, fixtureEnv("umbra", theme.None, "en"), 80, 24),
		msgs.Stored{Found: true, Components: []string{"shell"}, Shell: "fish"})
	if args := strings.Join(m.d.Args(), " "); !strings.Contains(args, "--shell fish") {
		t.Errorf("args %s", args)
	}
}

func nativeEnv() sys.Env {
	e := fixtureEnv("umbra", theme.None, "en")
	e.Platform = "arch"
	return e
}

// The Shell screen at 80×24 in each color depth, in es, and native (ux-spec §8).
func TestShellGolden(t *testing.T) {
	for pn, p := range profiles {
		m := started(t, fixtureEnv("umbra", p, "en"), 80, 24)
		m, _ = press(m, "enter", "enter", "enter", "down")
		checkGolden(t, "shell_fish_"+pn, m.Content())
	}
	m := started(t, fixtureEnv("umbra", theme.None, "es"), 80, 24)
	m, _ = press(m, "enter", "enter", "enter", "down", "down", "down")
	checkGolden(t, "es_shell_pwsh7", m.Content())
	n := started(t, nativeEnv(), 80, 24)
	n, _ = press(n, "enter", "enter", "enter")
	checkGolden(t, "shell_native", n.Content())
}
