package catalog

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

var platforms = []string{"wsl-ubuntu", "wsl-arch", "ubuntu", "arch", "omarchy"}

func envDir(t *testing.T) string {
	t.Helper()
	d, err := filepath.Abs(filepath.Join("..", "..", "env", "wsl"))
	if err != nil {
		t.Fatal(err)
	}
	return d
}

func load(t *testing.T) Catalog {
	t.Helper()
	f, err := os.Open(filepath.Join(envDir(t), "install", "components.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	c, err := Parse(f)
	if err != nil {
		t.Fatal(err)
	}
	return c
}

// bashSelector runs a selector.sh function: the bash side is the oracle (ADR 0039, contract C2).
func bashSelector(t *testing.T, env []string, fn string, args ...string) string {
	t.Helper()
	d := envDir(t)
	script := `source "$UM_ENV_DIR/install/common.sh"; source "$UM_ENV_DIR/install/selector.sh"; "$@"`
	cmd := exec.Command("bash", append([]string{"-c", script, "_", fn}, args...)...)
	cmd.Env = append([]string{"UM_ENV_DIR=" + d, "PATH=" + os.Getenv("PATH"), "HOME=" + t.TempDir()}, env...)
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("bash %s %v: %v", fn, args, err)
	}
	return strings.TrimRight(string(out), "\n")
}

func TestItemsMatchSelectorItems(t *testing.T) {
	c := load(t)
	for _, p := range platforms {
		var lines []string
		for _, it := range c.For(p) {
			lines = append(lines, it.ID+"|"+it.Label["en"]+"|"+strings.Join(it.Components, ","))
		}
		if got, want := strings.Join(lines, "\n"), bashSelector(t, nil, "selector_items", p); got != want {
			t.Errorf("%s:\n go:   %q\n bash: %q", p, got, want)
		}
	}
}

func TestDefaultsMatchSelectorDefaults(t *testing.T) {
	c := load(t)
	for _, p := range platforms {
		for _, desktop := range []bool{false, true} {
			for _, access := range []bool{false, true} {
				var env []string
				if desktop {
					env = append(env, "XDG_CURRENT_DESKTOP=test")
				}
				a := "0"
				if access {
					a = "1"
				}
				got := strings.Join(c.Defaults(p, desktop, access), ",")
				if want := bashSelector(t, env, "selector_defaults", p, a); got != want {
					t.Errorf("%s desktop=%v access=%v: go %q, bash %q", p, desktop, access, got, want)
				}
			}
		}
	}
}

func TestEveryItemHasBothLanguagesAndPhases(t *testing.T) {
	for _, it := range load(t).Items {
		for _, l := range []string{"en", "es"} {
			if it.Label[l] == "" || it.Summary[l] == "" {
				t.Errorf("%s/%s: missing %s label or summary", it.ID, it.Platforms, l)
			}
		}
		if len(it.Scripts) == 0 {
			t.Errorf("%s: no scripts (phases)", it.ID)
		}
	}
}

func TestParseRejectsBadInput(t *testing.T) {
	header := strings.Join(Columns, "\t")
	row := "x\tall\tx\tyes\tX\tX\tx\tx\t-\t-\ts.sh\t-\tsame\tcomponents"
	cases := map[string]string{
		"no schema line":   header + "\n" + row + "\n",
		"later schema":     "# schema 3 ·\n" + header + "\n" + row + "\n",
		"older schema":     "# schema 1 ·\n" + header + "\n" + row + "\n",
		"wrong header":     "# schema 2 ·\n" + strings.Replace(header, "label_es", "label_fr", 1) + "\n" + row + "\n",
		"missing a column": "# schema 2 ·\n" + header + "\n" + strings.TrimSuffix(row, "\tcomponents") + "\n",
	}
	for name, in := range cases {
		if _, err := Parse(strings.NewReader(in)); err == nil {
			t.Errorf("%s: want an error", name)
		}
	}
	c, err := Parse(strings.NewReader("# schema 2 ·\n" + header + "\n" + row + "\n"))
	if err != nil || len(c.Items) != 1 || c.Items[0].Installs != "" || c.Items[0].Scripts[0] != "s.sh" {
		t.Errorf("valid input: %+v, %v", c, err)
	}
}

func TestOffered(t *testing.T) {
	cases := []struct {
		set, p string
		want   bool
	}{
		{"all", "omarchy", true}, {"!omarchy", "omarchy", false}, {"!omarchy", "arch", true},
		{"wsl-ubuntu,wsl-arch", "wsl-arch", true}, {"wsl-ubuntu,wsl-arch", "arch", false},
	}
	for _, tc := range cases {
		if got := (Item{Platforms: tc.set}).Offered(tc.p); got != tc.want {
			t.Errorf("Offered(%q, %q) = %v", tc.set, tc.p, got)
		}
	}
}
