package plan

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/Robertcl795/umbra-bootstrapper/internal/catalog"
)

func load(t *testing.T) (catalog.Catalog, string) {
	t.Helper()
	d, err := filepath.Abs(filepath.Join("..", "..", "env", "wsl"))
	if err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(filepath.Join(d, "install", "components.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	c, err := catalog.Parse(f)
	if err != nil {
		t.Fatal(err)
	}
	return c, d
}

// Contract C1: Go expands items exactly as items_to_components in selector.sh does.
func TestComponentsMatchItemsToComponents(t *testing.T) {
	c, d := load(t)
	script := `source "$UM_ENV_DIR/install/common.sh"; source "$UM_ENV_DIR/install/selector.sh"; items_to_components "$1" "$2"`
	for _, p := range []string{"wsl-ubuntu", "wsl-arch", "ubuntu", "arch", "omarchy"} {
		var all []string
		for _, it := range c.For(p) {
			all = append(all, it.ID)
		}
		sels := [][]string{all, c.Defaults(p, false, false), c.Defaults(p, true, true), {"packages"},
			{"umbra-ai", "shell", "packages"}, {"nvim", "desktop", "wsl", "k8s"}, {"typo", "shell"}}
		for _, sel := range sels {
			cmd := exec.Command("bash", "-c", script, "_", p, strings.Join(sel, ","))
			cmd.Env = []string{"UM_ENV_DIR=" + d, "PATH=" + os.Getenv("PATH"), "HOME=" + t.TempDir()}
			out, err := cmd.Output() // stdout only: the warnings for unknown ids go to stderr
			if err != nil {
				t.Fatalf("bash %s %v: %v", p, sel, err)
			}
			got, _ := Components(c, p, sel)
			if want := strings.TrimSpace(string(out)); strings.Join(got, ",") != want {
				t.Errorf("%s %v: go %q, bash %q", p, sel, strings.Join(got, ","), want)
			}
		}
	}
}

func TestComponentsReportsUnknownIDs(t *testing.T) {
	c, _ := load(t)
	_, unknown := Components(c, "omarchy", []string{"packages", "nvim", "desktop"})
	if !slices.Equal(unknown, []string{"nvim", "desktop"}) {
		t.Errorf("unknown = %v", unknown)
	}
}

func TestArgs(t *testing.T) {
	c, _ := load(t)
	cases := []struct {
		name     string
		platform string
		sel      Selection
		want     string
	}{
		{"personal with k8s", "wsl-arch",
			Selection{Profile: "personal", Items: []string{"shell", "packages", "k8s"}, Variant: "void"},
			"--yes --profile personal --components packages,shell,k8s --theme void --enable-k8s"},
		{"work with skip, no k8s, no variant", "ubuntu",
			Selection{Profile: "work", Items: []string{"umbra-ai", "prompt"}, Skip: []string{"vault", "ollama"}},
			"--yes --profile work --components prompt,ai-cli,ai-standard,um,vault,ollama --skip vault,ollama --disable-k8s"},
	}
	for _, tc := range cases {
		if got := strings.Join(Args(c, tc.platform, tc.sel), " "); got != tc.want {
			t.Errorf("%s:\n got  %s\n want %s", tc.name, got, tc.want)
		}
	}
}
