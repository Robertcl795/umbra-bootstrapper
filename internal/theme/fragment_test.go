package theme

import (
	"encoding/json"
	"flag"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

var update = flag.Bool("update", false, "rewrite testdata")

// ADR 0043: the fragment's schemes are the generated Windows Terminal schemes
// (themes/generate.py → themes/terminals/windows-terminal), built here from the same tokens.
func TestSchemesMatchTheGeneratedWindowsTerminalFiles(t *testing.T) {
	files := map[string]string{"umbra": "umbra.json", "void": "umbra-void.json", "lux": "umbra-lux.json"}
	for _, v := range Variants {
		raw, err := os.ReadFile(filepath.Join("..", "..", "themes", "terminals", "windows-terminal", files[v]))
		if err != nil {
			t.Fatal(err)
		}
		var want, got map[string]string
		if err := json.Unmarshal(raw, &want); err != nil {
			t.Fatal(err)
		}
		b, _ := json.Marshal(WTScheme(v))
		if err := json.Unmarshal(b, &got); err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%s:\n got %v\nwant %v", v, got, want)
		}
	}
}

// The fragment adds all three schemes and its own profile; it never updates another profile.
func TestFragmentAddsTheSchemesAndItsOwnProfile(t *testing.T) {
	b, err := Fragment("archlinux", "void", NerdFont)
	if err != nil {
		t.Fatal(err)
	}
	golden := filepath.Join("testdata", "wt-fragment.json")
	if *update {
		if err := os.WriteFile(golden, b, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	want, err := os.ReadFile(golden)
	if err != nil {
		t.Fatalf("%v (run go test ./internal/theme -update)", err)
	}
	if string(b) != string(want) {
		t.Fatalf("fragment differs from %s:\n%s", golden, b)
	}
	var f struct {
		Profiles []map[string]any `json:"profiles"`
		Schemes  []map[string]any `json:"schemes"`
		Updates  any              `json:"updates"`
	}
	if err := json.Unmarshal(b, &f); err != nil {
		t.Fatal(err)
	}
	if len(f.Schemes) != 3 || len(f.Profiles) != 1 {
		t.Fatalf("%d schemes, %d profiles", len(f.Schemes), len(f.Profiles))
	}
	p := f.Profiles[0]
	if p["name"] != "Umbra · archlinux" || p["commandline"] != "wsl.exe -d archlinux --cd ~" || p["colorScheme"] != "Umbra Void" {
		t.Fatalf("profile: %v", p)
	}
	for _, prof := range f.Profiles {
		if _, ok := prof["updates"]; ok {
			t.Fatal("a profile updates another one")
		}
	}
}

func TestFragmentRejectsAnUnknownVariantOrEmptyDistro(t *testing.T) {
	if _, err := Fragment("archlinux", "neon", NerdFont); err == nil {
		t.Fatal("unknown variant accepted")
	}
	if _, err := Fragment("", "void", NerdFont); err == nil {
		t.Fatal("empty distro accepted")
	}
}
