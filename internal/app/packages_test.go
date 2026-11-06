package app

import (
	"slices"
	"strings"
	"testing"

	"github.com/Robertcl795/umbra-bootstrapper/internal/catalog"
	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
)

// atComponents is the components screen with the cursor on the first row (packages).
func atComponents(t *testing.T) Model {
	t.Helper()
	m := started(t, fixtureEnv("umbra", theme.None, "en"), 80, 24)
	m, _ = press(m, "enter", "enter")
	if m.screen != Components {
		t.Fatalf("screen %d, want Components", m.screen)
	}
	return m
}

// rowOf is the editor row of a package of the item under the cursor.
func rowOf(t *testing.T, m Model, name string) int {
	t.Helper()
	i := slices.IndexFunc(m.d.Packages(m.d.Items[m.ccur].ID), func(r catalog.Package) bool { return r.Name == name })
	if i < 0 {
		t.Fatalf("%s is not a package of %s", name, m.d.Items[m.ccur].ID)
	}
	return i
}

func down(n int) []string {
	keys := make([]string, n)
	for i := range keys {
		keys[i] = "down"
	}
	return keys
}

// e opens the package editor; space leaves a package out; esc goes back; the run gets
// --skip-packages (plan installer-packages-shell, R3).
func TestEditPackagesLeavesOnePackageOut(t *testing.T) {
	m := atComponents(t)
	if !strings.Contains(m.Content(), "git: ") {
		t.Fatal("the detail does not list the packages")
	}
	m, _ = press(m, "e")
	if !m.editing || !strings.HasPrefix(m.Title(), "Umbra setup · editor packages") {
		t.Fatalf("e: editing %v, title %q", m.editing, m.Title())
	}
	m, _ = press(m, down(rowOf(t, m, "eza"))...)
	m, _ = press(m, "space")
	m, _ = press(m, "esc")
	if m.editing || m.screen != Components {
		t.Fatalf("esc: editing %v, screen %d", m.editing, m.screen)
	}
	if !strings.Contains(m.Content(), "1 out") {
		t.Error("the components row does not say a package was left out")
	}
	if args := strings.Join(m.d.Args(), " "); !strings.Contains(args, "--skip-packages eza") {
		t.Errorf("args %s", args)
	}
}

// A package the component needs cannot be left out; a component without optional packages has
// no editor (Q1).
func TestNeededPackagesAndReadOnlyComponents(t *testing.T) {
	m := atComponents(t)
	m, _ = press(m, "e")
	m, _ = press(m, down(rowOf(t, m, "git"))...)
	m, _ = press(m, "space", "n")
	if m.d.Sel.SkipPkgs["git"] {
		t.Error("git (needed) was left out")
	}
	if !m.d.Sel.SkipPkgs["fzf"] {
		t.Error("n did not leave out the optional packages")
	}
	m, _ = press(m, "a", "esc")
	if args := strings.Join(m.d.Args(), " "); strings.Contains(args, "--skip-packages") {
		t.Errorf("a put every package back, args %s", args)
	}
	m, _ = press(m, "down", "e") // shell: its packages are listed, not edited
	if m.editing {
		t.Error("e opened an editor for shell")
	}
}

// Packages of a component that is not installed are not passed on.
func TestSkipsOfAnUntickedComponentAreDropped(t *testing.T) {
	m := atComponents(t)
	m, _ = press(m, "e")
	m, _ = press(m, down(rowOf(t, m, "fzf"))...)
	m, _ = press(m, "space", "esc", "space") // leave fzf out, then untick packages
	if args := strings.Join(m.d.Args(), " "); strings.Contains(args, "--skip-packages") {
		t.Errorf("args %s", args)
	}
}

// A re-run starts from the stored skip_packages.
func TestRerunKeepsTheStoredSkips(t *testing.T) {
	m := send(started(t, fixtureEnv("umbra", theme.None, "en"), 80, 24),
		msgs.Stored{Found: true, Components: []string{"packages"}, SkipPackages: []string{"yazi"}})
	if args := strings.Join(m.d.Args(), " "); !strings.Contains(args, "--skip-packages yazi") {
		t.Errorf("args %s", args)
	}
}

// The editor at 80×24 in each color depth and in es, scrolled to the middle once (ux-spec §8).
func TestPackagesGolden(t *testing.T) {
	for pn, p := range profiles {
		m := started(t, fixtureEnv("umbra", p, "en"), 80, 24)
		m, _ = press(m, "enter", "enter", "e")
		checkGolden(t, "packages_umbra_"+pn, m.Content())
	}
	m := started(t, fixtureEnv("umbra", theme.None, "es"), 80, 24)
	m, _ = press(m, "enter", "enter", "e")
	m, _ = press(m, down(20)...)
	m, _ = press(m, "space")
	checkGolden(t, "es_packages_scrolled", m.Content())
	m, _ = press(m, "esc")
	checkGolden(t, "es_components_leftout", m.Content())
}

// Review names the packages left out (R6).
func TestReviewListsThePackagesLeftOut(t *testing.T) {
	m := atComponents(t)
	m, _ = press(m, "e")
	m, _ = press(m, down(rowOf(t, m, "yazi"))...)
	m, _ = press(m, "space", "esc", "enter", "enter", "enter")
	if m.screen != Review {
		t.Fatalf("screen %d, want Review", m.screen)
	}
	if !strings.Contains(m.Content(), "left out   yazi") {
		t.Errorf("review:\n%s", m.Content())
	}
}
