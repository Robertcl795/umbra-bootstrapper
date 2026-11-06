package catalog

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func loadPackages(t *testing.T) Packages {
	t.Helper()
	f, err := os.Open(filepath.Join(envDir(t), "install", "packages.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	p, err := ParsePackages(f)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

// bashRows runs common.sh's pkg_rows: the install scripts are the oracle for what the screen lists.
func bashRows(t *testing.T, platform, component string) string {
	t.Helper()
	script := `source "$UM_ENV_DIR/install/common.sh"; pkg_rows "$1" | cut -f1`
	cmd := exec.Command("bash", "-c", script, "_", component)
	cmd.Env = []string{"UM_ENV_DIR=" + envDir(t), "UM_OS=" + OS(platform), "PATH=" + os.Getenv("PATH"), "HOME=" + t.TempDir()}
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("bash pkg_rows %s on %s: %v", component, platform, err)
	}
	return strings.TrimRight(string(out), "\n")
}

func TestPackagesMatchTheInstallScripts(t *testing.T) {
	p, c := loadPackages(t), load(t)
	for _, pl := range platforms {
		for _, it := range c.For(pl) {
			var names []string
			for _, r := range p.For(it.ID, pl) {
				names = append(names, r.Name)
			}
			if got, want := strings.Join(names, "\n"), bashRows(t, pl, it.ID); got != want {
				t.Errorf("%s on %s:\n go:   %q\n bash: %q", it.ID, pl, got, want)
			}
		}
	}
}

func TestPackagesTable(t *testing.T) {
	p, c := loadPackages(t), load(t)
	ids := map[string]bool{}
	for _, it := range c.Items {
		ids[it.ID] = true
	}
	skippable := map[string]string{}
	for _, r := range p.Rows {
		if !ids[r.Component] {
			t.Errorf("%s: component %q is not in components.tsv", r.Name, r.Component)
		}
		if r.Desc["en"] == "" || r.Desc["es"] == "" {
			t.Errorf("%s (%s): a description is missing", r.Name, r.Component)
		}
		// --skip-packages takes bare names: a skippable name belongs to one component.
		if r.Skip {
			if other, ok := skippable[r.Name]; ok && other != r.Component {
				t.Errorf("%s is skippable in %s and %s", r.Name, other, r.Component)
			}
			skippable[r.Name] = r.Component
		}
	}
	// Q1 of the plan: Packages, Language toolchains and Kubernetes tools can be edited; the rest
	// only list what they install.
	for _, it := range c.Items {
		want := it.ID == "packages" || it.ID == "lang" || it.ID == "k8s"
		for _, pl := range platforms {
			if !it.Offered(pl) {
				continue
			}
			if got := p.Editable(it.ID, pl); got != want {
				t.Errorf("%s on %s: editable %v, want %v", it.ID, pl, got, want)
			}
		}
	}
}

func TestParsePackagesRejectsAnotherSchema(t *testing.T) {
	if _, err := ParsePackages(strings.NewReader("# schema 2 · x\n")); err == nil {
		t.Error("schema 2 was accepted")
	}
	if _, err := ParsePackages(strings.NewReader("# schema 1 · x\nname\tcomponent\n")); err == nil {
		t.Error("a short header was accepted")
	}
}

func TestOS(t *testing.T) {
	for pl, want := range map[string]string{"wsl-ubuntu": "ubuntu", "wsl-arch": "arch", "ubuntu": "ubuntu", "omarchy": "omarchy"} {
		if got := OS(pl); got != want {
			t.Errorf("OS(%s) = %s, want %s", pl, got, want)
		}
	}
}
