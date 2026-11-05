package events

import (
	"bufio"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParse(t *testing.T) {
	ev, err := Parse("v1\t2026-11-04T18:02:03.456Z\tphase\trun_onchange_before_30-prompt.sh\tstart\t\n")
	want := Event{At: time.Date(2026, 11, 4, 18, 2, 3, 456e6, time.UTC), Kind: "phase", Phase: "run_onchange_before_30-prompt.sh", State: "start"}
	if err != nil || ev != want {
		t.Fatalf("got %+v, %v", ev, err)
	}
	ev, err = Parse("v1\t2026-11-04T18:02:03.456Z\tlog\t-\twarn\ta message\twith a tab kept")
	if err != nil || ev.Phase != "" || ev.Message != "a message\twith a tab kept" {
		t.Errorf("log line: %+v, %v", ev, err)
	}
}

func TestParseRejects(t *testing.T) {
	bad := map[string]string{
		"empty":         "",
		"not an event":  "[INFO] hello",
		"few fields":    "v1\t2026-11-04T18:02:03.456Z\tphase\tx\tok",
		"bad timestamp": "v1\tyesterday\tphase\tx\tok\t",
		"unknown kind":  "v1\t2026-11-04T18:02:03.456Z\tmetric\tx\tok\t",
		"wrong state":   "v1\t2026-11-04T18:02:03.456Z\tlog\tx\tok\t",
	}
	for name, line := range bad {
		if _, err := Parse(line); err == nil {
			t.Errorf("%s: want an error", name)
		}
	}
	if _, err := Parse("v2\t2026-11-04T18:02:03.456Z\tphase\tx\tok\t\tnew"); !errors.Is(err, ErrUnknownVersion) {
		t.Errorf("v2: want ErrUnknownVersion, got %v", err)
	}
}

// Contract C3 across languages: every line the bash helpers write parses, with the right fields.
func TestParsesWhatBashWrites(t *testing.T) {
	d, _ := filepath.Abs(filepath.Join("..", "..", "env", "wsl"))
	file := filepath.Join(t.TempDir(), "events")
	script := `source "$UM_ENV_DIR/install/common.sh"; set +e
phase_start run_onchange_before_40-nvim.sh
log_info "installing neovim"
log_warn "slow mirror"
phase_gate nvim "nvim does not start" false
log_error "ñandú: UTF-8 survives"`
	cmd := exec.Command("bash", "-c", script)
	cmd.Env = []string{"UM_ENV_DIR=" + d, "UM_EVENTS=" + file, "PATH=" + os.Getenv("PATH"), "HOME=" + t.TempDir()}
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("bash: %v\n%s", err, out)
	}
	f, err := os.Open(file)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	var got []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		ev, err := Parse(sc.Text())
		if err != nil {
			t.Fatalf("line %q: %v", sc.Text(), err)
		}
		if time.Since(ev.At) > time.Minute || time.Since(ev.At) < 0 {
			t.Errorf("timestamp %v is not now", ev.At)
		}
		got = append(got, strings.Join([]string{ev.Kind, ev.Phase, ev.State, ev.Message}, "|"))
	}
	want := []string{
		"phase|run_onchange_before_40-nvim.sh|start|",
		"log|run_onchange_before_40-nvim.sh|info|installing neovim",
		"log|run_onchange_before_40-nvim.sh|warn|slow mirror",
		"phase|run_onchange_before_40-nvim.sh|fail|nvim does not start",
		"log|run_onchange_before_40-nvim.sh|error|ñandú: UTF-8 survives",
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Errorf("events:\n%s\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}
