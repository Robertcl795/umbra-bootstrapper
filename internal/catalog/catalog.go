// Package catalog reads the one component list, env/wsl/install/components.tsv (ADR 0039).
// It is pure: it parses from an io.Reader and never touches the file system itself.
package catalog

import (
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"strings"
)

// Schema is the catalog schema this package reads (the "# schema N" comment on line 1).
const Schema = 2

// Columns are the schema 2 columns, in file order. Schema 2 added screen.
var Columns = []string{"id", "platforms", "components", "default", "label_en", "label_es",
	"summary_en", "summary_es", "installs", "deploys", "scripts", "check", "work", "screen"}

// Item is one catalog row: a component as offered on a set of platforms.
type Item struct {
	ID         string
	Platforms  string   // "all", "!<platform>" or a comma list
	Components []string // the --components expansion
	Default    string   // yes, no, desktop-session, ai-access
	Label      map[string]string
	Summary    map[string]string
	Installs   string
	Deploys    string
	Scripts    []string // chezmoi scripts without .tmpl: the phases of this item
	Check      string   // test under env/wsl/tests/, or ""
	Work       string   // same, limited, off
	Screen     string   // components; shell-choice (the Shell screen's choice of shell); shell-extra (a box there)
}

// Catalog is every row, in file (menu) order.
type Catalog struct{ Items []Item }

// Parse reads a schema 2 catalog. Comments start with '#', '-' is an empty field.
func Parse(r io.Reader) (Catalog, error) {
	raw, err := io.ReadAll(r)
	if err != nil {
		return Catalog{}, err
	}
	text := string(raw)
	first, _, _ := strings.Cut(text, "\n")
	if !strings.HasPrefix(first, fmt.Sprintf("# schema %d ", Schema)) {
		return Catalog{}, fmt.Errorf("catalog: line 1 must start with '# schema %d '", Schema)
	}
	cr := csv.NewReader(strings.NewReader(text))
	cr.Comma = '\t'
	cr.Comment = '#'
	cr.LazyQuotes = true
	cr.FieldsPerRecord = len(Columns)
	recs, err := cr.ReadAll()
	if err != nil {
		return Catalog{}, fmt.Errorf("catalog: %w", err)
	}
	if len(recs) == 0 || strings.Join(recs[0], "\t") != strings.Join(Columns, "\t") {
		return Catalog{}, errors.New("catalog: header row does not match schema 2")
	}
	var c Catalog
	for _, f := range recs[1:] {
		v := func(i int) string {
			if f[i] == "-" {
				return ""
			}
			return f[i]
		}
		c.Items = append(c.Items, Item{
			ID: f[0], Platforms: f[1], Components: split(v(2)), Default: f[3],
			Label:    map[string]string{"en": f[4], "es": f[5]},
			Summary:  map[string]string{"en": f[6], "es": f[7]},
			Installs: v(8), Deploys: v(9), Scripts: split(v(10)), Check: v(11), Work: f[12], Screen: f[13],
		})
	}
	return c, nil
}

func split(s string) []string {
	if s == "" {
		return nil
	}
	return strings.Split(s, ",")
}

// Offered reports whether the item's platform set includes platform.
func (it Item) Offered(platform string) bool {
	switch {
	case it.Platforms == "all":
		return true
	case strings.HasPrefix(it.Platforms, "!"):
		return platform != it.Platforms[1:]
	default:
		for _, p := range strings.Split(it.Platforms, ",") {
			if p == platform {
				return true
			}
		}
		return false
	}
}

// For returns the items offered on platform, in menu order.
func (c Catalog) For(platform string) []Item {
	var out []Item
	for _, it := range c.Items {
		if it.Offered(platform) {
			out = append(out, it)
		}
	}
	return out
}

// Defaults returns the ids pre-selected on platform: "yes" always, "desktop-session" only with a
// desktop session, "ai-access" only with Umbra AI access, "no" never (as selector_defaults).
func (c Catalog) Defaults(platform string, desktop, access bool) []string {
	var out []string
	for _, it := range c.For(platform) {
		switch {
		case it.Default == "yes",
			it.Default == "desktop-session" && desktop,
			it.Default == "ai-access" && access:
			out = append(out, it.ID)
		}
	}
	return out
}
