package main

import (
	"encoding/json"
	"os"
	"os/exec"
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
