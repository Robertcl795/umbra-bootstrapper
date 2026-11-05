package i18n

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"
	"testing"
)

func keys(m map[string]string) []string {
	var out []string
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func TestBothLanguagesHaveTheSameKeys(t *testing.T) {
	en, es := keys(Catalog("en")), keys(Catalog("es"))
	if !slices.Equal(en, es) {
		t.Errorf("en and es keys differ:\n en %v\n es %v", en, es)
	}
	for _, l := range Langs {
		for k, v := range Catalog(l) {
			if strings.TrimSpace(v) == "" {
				t.Errorf("%s: %s is empty", l, k)
			}
		}
	}
}

// Every key is used by the code, and every key the code looks up exists. A key counts as used
// when it appears as a string literal in non-test Go; keys built at run time are listed by prefix.
func TestKeysUsedAndKnown(t *testing.T) {
	lookup := regexp.MustCompile(`\b(?:T|tr)\("([a-z0-9.]+)"`)
	literal := regexp.MustCompile(`"([a-z0-9]+(?:\.[a-z0-9]+)+)"`)
	cat := Catalog("en")
	used := map[string]bool{}
	_ = filepath.Walk(filepath.Join("..", ".."), func(p string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || !strings.HasSuffix(p, ".go") || strings.HasSuffix(p, "_test.go") {
			return nil
		}
		b, _ := os.ReadFile(p)
		for _, m := range lookup.FindAllSubmatch(b, -1) {
			used[string(m[1])] = true
			if _, ok := cat[string(m[1])]; !ok && !strings.HasSuffix(string(m[1]), ".") {
				t.Errorf("%s looks up %q, which is not in the catalog", p, m[1])
			}
		}
		for _, m := range literal.FindAllSubmatch(b, -1) {
			used[string(m[1])] = true
		}
		return nil
	})
	// Built at run time: "step."+id, "theme."+variant, "comp.work."+work, "profile."+p(+".more").
	for _, prefix := range []string{"step.", "theme.umbra", "theme.void", "theme.lux", "comp.work.", "profile.personal", "profile.work"} {
		for k := range cat {
			if strings.HasPrefix(k, prefix) {
				used[k] = true
			}
		}
	}
	for k := range cat {
		if !used[k] {
			t.Errorf("key %q is never used", k)
		}
	}
}

func TestResolve(t *testing.T) {
	get := func(m map[string]string) func(string) string { return func(k string) string { return m[k] } }
	cases := []struct {
		env  map[string]string
		want string
	}{
		{map[string]string{"UM_LANG": "es", "LANG": "en_US.UTF-8"}, "es"},
		{map[string]string{"LANG": "es_MX.UTF-8"}, "es"},
		{map[string]string{"LC_ALL": "C", "LANG": "es_MX.UTF-8"}, "en"},
		{map[string]string{}, "en"},
	}
	for _, tc := range cases {
		if got := Resolve(get(tc.env)); got != tc.want {
			t.Errorf("%v: %s", tc.env, got)
		}
	}
	if got := New("es")("comp.count", "n", "3", "total", "10"); got != "3 de 10 seleccionados" {
		t.Errorf("placeholders: %q", got)
	}
}
