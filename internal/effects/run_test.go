package effects

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
)

// The password for stage 1's user reaches the child only as a 0600 file in a 0700 dir, and the
// dir is gone once the child exited.
func TestStartPassesThePasswordAsAFileAndRemovesIt(t *testing.T) {
	tmp := t.TempDir()
	fake := filepath.Join(tmp, "install.sh")
	script := `f="$UM_USER_PASSWORD_FILE"; d=$(dirname "$f")
echo "file=$f"; echo "perm=$(stat -c %a "$f") dirperm=$(stat -c %a "$d")"; echo "content=$(cat "$f")"`
	if err := os.WriteFile(fake, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("UM_SETUP_INSTALL", fake)
	t.Setenv("XDG_STATE_HOME", filepath.Join(tmp, "state"))
	started, ok := Start(tmp, []string{"--yes"}, "pass word")().(msgs.RunStarted)
	if !ok {
		t.Fatal("did not start")
	}
	if code := Wait(started.PID)().(msgs.RunExited).Code; code != 0 {
		t.Fatalf("exit %d", code)
	}
	log, _ := os.ReadFile(started.Log)
	out := string(log)
	if !strings.Contains(out, "perm=600 dirperm=700") || !strings.Contains(out, "content=pass word") {
		t.Fatalf("child saw:\n%s", out)
	}
	file := strings.TrimPrefix(strings.SplitN(out, "\n", 2)[0], "file=")
	if _, err := os.Stat(filepath.Dir(file)); !os.IsNotExist(err) {
		t.Errorf("password dir still there after the run: %s", filepath.Dir(file))
	}
	started2 := Start(tmp, []string{"--yes"}, "")().(msgs.RunStarted)
	Wait(started2.PID)()
	if log2, _ := os.ReadFile(started2.Log); !strings.Contains(string(log2), "file=\n") && !strings.HasPrefix(string(log2), "file=\n") {
		t.Errorf("no password: no file expected, got:\n%s", log2)
	}
}
