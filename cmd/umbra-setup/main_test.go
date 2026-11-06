package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestMain lets a test run this binary as umbra-setup: UM_TEST_MAIN=1 calls run() with the args.
func TestMain(m *testing.M) {
	if os.Getenv("UM_TEST_MAIN") == "1" {
		os.Args = append([]string{"umbra-setup"}, strings.Split(os.Getenv("UM_TEST_ARGS"), "\x1f")...)
		os.Exit(run())
	}
	os.Exit(m.Run())
}

func setup(t *testing.T, env []string, args ...string) (string, int) {
	t.Helper()
	cmd := exec.Command(os.Args[0])
	cmd.Env = append(os.Environ(), append(env, "UM_TEST_MAIN=1", "UM_TEST_ARGS="+strings.Join(args, "\x1f"))...)
	out, err := cmd.Output()
	code := 0
	if e, ok := err.(*exec.ExitError); ok {
		code = e.ExitCode()
	} else if err != nil {
		t.Fatal(err)
	}
	return string(out), code
}

// terminal.sh (ADR 0043) gets the fragment from here: no terminal needed, nothing written.
func TestWTFragmentPrintsTheFragmentForThisDistro(t *testing.T) {
	out, code := setup(t, []string{"WSL_DISTRO_NAME=Ubuntu-24.04"}, "--wt-fragment", "lux", "--wt-font", "Cascadia Mono")
	if code != 0 {
		t.Fatalf("exit %d: %s", code, out)
	}
	var f struct {
		Profiles []struct {
			Name, ColorScheme string
			Font              struct{ Face string }
		}
	}
	if err := json.Unmarshal([]byte(out), &f); err != nil {
		t.Fatalf("%v: %s", err, out)
	}
	p := f.Profiles[0]
	if p.Name != "Umbra · Ubuntu-24.04" || p.ColorScheme != "Umbra Lux" || p.Font.Face != "Cascadia Mono" {
		t.Fatalf("profile %+v", p)
	}
}

func TestWTFragmentFailsWithoutADistroOrWithAnUnknownVariant(t *testing.T) {
	if _, code := setup(t, []string{"WSL_DISTRO_NAME="}, "--wt-fragment", "lux"); code != 1 {
		t.Fatalf("no distro: exit %d, want 1", code)
	}
	if _, code := setup(t, []string{"WSL_DISTRO_NAME=x"}, "--wt-fragment", "neon"); code != 1 {
		t.Fatalf("unknown variant: exit %d, want 1", code)
	}
}

const wtSample = `{
    "defaultProfile": "{04d0c07a-b717-5790-a033-fbd379a82afb}", // Ubuntu
    "profiles": { "list": [
        { "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}", "name": "PowerShell", "source": "Windows.Terminal.PowershellCore" },
        { "guid": "{04d0c07a-b717-5790-a033-fbd379a82afb}", "name": "Ubuntu" }
    ] }
}
`

// Make default (plan installer-packages-shell, T4; ADR 0043 as amended): --wt-status reads,
// --wt-default-pwsh7 backs the file up and changes only defaultProfile.
func TestWTDefaultPowerShell7(t *testing.T) {
	p := t.TempDir() + "/settings.json"
	if err := os.WriteFile(p, []byte(wtSample), 0o644); err != nil {
		t.Fatal(err)
	}
	out, code := setup(t, nil, "--wt-status", p)
	if code != 0 || out != "default={04d0c07a-b717-5790-a033-fbd379a82afb}\npwsh7={574e775e-4f2a-5b96-ac1e-a2962a402336}\n" {
		t.Fatalf("status: exit %d %q", code, out)
	}
	out, code = setup(t, nil, "--wt-default-pwsh7", p)
	if code != 0 || !strings.HasPrefix(out, "backup=") {
		t.Fatalf("set: exit %d %q", code, out)
	}
	backup := strings.TrimSpace(strings.TrimPrefix(out, "backup="))
	if b, err := os.ReadFile(backup); err != nil || string(b) != wtSample {
		t.Errorf("backup %s: %v", backup, err)
	}
	b, _ := os.ReadFile(p)
	want := strings.Replace(wtSample, "{04d0c07a-b717-5790-a033-fbd379a82afb}\", // Ubuntu", "{574e775e-4f2a-5b96-ac1e-a2962a402336}\", // Ubuntu", 1)
	if string(b) != want {
		t.Errorf("settings.json:\n%s", b)
	}
	if out, code = setup(t, nil, "--wt-status", p); !strings.HasPrefix(out, "default={574e775e") || code != 0 {
		t.Errorf("after: %q", out)
	}
}

// Without the PowerShell 7 profile (Windows Terminal has not started since pwsh was installed)
// nothing is written and the exit code says so.
func TestWTDefaultPowerShell7WithoutTheProfile(t *testing.T) {
	p := t.TempDir() + "/settings.json"
	text := strings.Replace(wtSample, "Windows.Terminal.PowershellCore", "x", 1)
	_ = os.WriteFile(p, []byte(text), 0o644)
	if _, code := setup(t, nil, "--wt-default-pwsh7", p); code != 3 {
		t.Fatalf("exit %d, want 3", code)
	}
	if b, _ := os.ReadFile(p); string(b) != text {
		t.Error("the file changed")
	}
	if matches, _ := filepath.Glob(p + ".umbra-*"); len(matches) != 0 {
		t.Errorf("a backup was made: %v", matches)
	}
}
