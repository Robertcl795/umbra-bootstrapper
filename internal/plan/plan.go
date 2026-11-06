// Package plan turns a selection into the arguments of bootstrap.sh (ux-spec §2.3, contract C1).
// It is pure: the same selection always gives the same arguments.
package plan

import (
	"slices"
	"strings"

	"github.com/Robertcl795/umbra-bootstrapper/internal/catalog"
)

// k8sComponent is the component that bootstrap.sh's --enable-k8s and --disable-k8s flags are
// about. install.sh names it the same way after its menu. The only allowed id literal (arch test).
const k8sComponent = "k8s"

// Selection is what the user picked.
type Selection struct {
	Profile string   // personal or work
	Items   []string // catalog ids
	Skip    []string // components to skip (--skip)
	Variant string   // umbra, void or lux

	SkipPackages []string // packages.tsv rows left out (--skip-packages), table order
	Shell        string   // the chosen shell (--shell), or "" when no shell item is installed
}

// Components expands item ids into the --components list, in menu order, like
// items_to_components in selector.sh. Ids the platform does not offer come back in unknown.
func Components(c catalog.Catalog, platform string, items []string) (comps, unknown []string) {
	offered := c.For(platform)
	for _, it := range offered {
		if slices.Contains(items, it.ID) {
			comps = append(comps, it.Components...)
		}
	}
	for _, id := range items {
		if !slices.ContainsFunc(offered, func(it catalog.Item) bool { return it.ID == id }) {
			unknown = append(unknown, id)
		}
	}
	return comps, unknown
}

// Command is the "Next time" line of Review: install.sh with exactly the arguments umbra-setup
// gives bootstrap.sh. install.sh forwards the flags it does not know (--theme, --enable-k8s), so
// running it gives the same chezmoi data as the TUI (contract C5).
func Command(args []string) string { return "install.sh " + strings.Join(args, " ") }

// Args returns the bootstrap.sh arguments for a selection. They equal the flags of
// `install.sh --yes --profile P --components C [--skip S] --theme V`, the "Next time" command of
// Review; Kubernetes is passed explicitly, as install.sh does after its menu.
func Args(c catalog.Catalog, platform string, s Selection) []string {
	comps, _ := Components(c, platform, s.Items)
	args := []string{"--yes", "--profile", s.Profile, "--components", strings.Join(comps, ",")}
	if len(s.Skip) > 0 {
		args = append(args, "--skip", strings.Join(s.Skip, ","))
	}
	if s.Shell != "" {
		args = append(args, "--shell", s.Shell)
	}
	if len(s.SkipPackages) > 0 {
		args = append(args, "--skip-packages", strings.Join(s.SkipPackages, ","))
	}
	if s.Variant != "" {
		args = append(args, "--theme", s.Variant)
	}
	if slices.Contains(comps, k8sComponent) {
		args = append(args, "--enable-k8s")
	} else {
		args = append(args, "--disable-k8s")
	}
	return args
}
