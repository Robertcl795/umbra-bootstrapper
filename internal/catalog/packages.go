package catalog

import (
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"strings"
)

// PackageColumns are the columns of env/wsl/install/packages.tsv (schema 1), in file order.
var PackageColumns = []string{"name", "component", "os", "source", "pkg", "cmd", "skip", "desc_en", "desc_es"}

// Package is one row of packages.tsv: a package a component installs on a set of OSes.
type Package struct {
	Name      string
	Component string            // a components.tsv id
	OS        string            // "all", "!<os>" or a comma list of ubuntu, arch, omarchy
	Source    string            // pm, pm-try or code
	Pkg       string            // the package manager's name ("" = Name)
	Cmd       string            // the doctor's command, a|b = either ("" = none)
	Skip      bool              // the user may leave it out (--skip-packages)
	Desc      map[string]string // en, es
}

// Packages is every row, in file order.
type Packages struct{ Rows []Package }

// ParsePackages reads a schema 1 packages table. Comments start with '#', '-' is an empty field.
func ParsePackages(r io.Reader) (Packages, error) {
	raw, err := io.ReadAll(r)
	if err != nil {
		return Packages{}, err
	}
	text := string(raw)
	first, _, _ := strings.Cut(text, "\n")
	if !strings.HasPrefix(first, fmt.Sprintf("# schema %d ", Schema)) {
		return Packages{}, fmt.Errorf("packages: line 1 must start with '# schema %d '", Schema)
	}
	cr := csv.NewReader(strings.NewReader(text))
	cr.Comma = '\t'
	cr.Comment = '#'
	cr.LazyQuotes = true
	cr.FieldsPerRecord = -1
	recs, err := cr.ReadAll()
	if err != nil {
		return Packages{}, fmt.Errorf("packages: %w", err)
	}
	if len(recs) == 0 || strings.Join(recs[0], "\t") != strings.Join(PackageColumns, "\t") {
		return Packages{}, errors.New("packages: header row does not match schema 1")
	}
	var p Packages
	for i, f := range recs[1:] {
		if len(f) != len(PackageColumns) {
			return Packages{}, fmt.Errorf("packages: row %d has %d fields, want %d", i+1, len(f), len(PackageColumns))
		}
		v := func(i int) string {
			if f[i] == "-" {
				return ""
			}
			return f[i]
		}
		p.Rows = append(p.Rows, Package{Name: f[0], Component: f[1], OS: f[2], Source: f[3], Pkg: v(4), Cmd: v(5),
			Skip: f[6] == "yes", Desc: map[string]string{"en": f[7], "es": f[8]}})
	}
	return p, nil
}

// OS is the install scripts' UM_OS for a platform: wsl-ubuntu and ubuntu are both ubuntu.
func OS(platform string) string { return strings.TrimPrefix(platform, "wsl-") }

// On reports whether the row is installed on platform (as common.sh's pkg_rows).
func (r Package) On(platform string) bool {
	os := OS(platform)
	switch {
	case r.OS == "all":
		return true
	case strings.HasPrefix(r.OS, "!"):
		return os != r.OS[1:]
	default:
		for _, o := range strings.Split(r.OS, ",") {
			if o == os {
				return true
			}
		}
		return false
	}
}

// For returns the rows of a component on platform, in file order.
func (p Packages) For(component, platform string) []Package {
	var out []Package
	for _, r := range p.Rows {
		if r.Component == component && r.On(platform) {
			out = append(out, r)
		}
	}
	return out
}

// Editable reports whether the user can leave out any of the component's packages on platform.
func (p Packages) Editable(component, platform string) bool {
	for _, r := range p.For(component, platform) {
		if r.Skip {
			return true
		}
	}
	return false
}
