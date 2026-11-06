// Command umbra-setup is the bootstrapper's TUI and Umbra's entry point (ADR 0037).
//
// It walks scan → profile → components → theme → review, then runs install.sh with the flags of
// the review's "Next time" line and follows its phases (ADR 0040), then the doctor. With
// --resume (from `umbra bootstrap resume`) it scans, then runs stage 2's bootstrap.sh with the
// staged selection from the environment and follows it the same way.
//
// Exit codes: 0 done (or the WSL restart point), 1 a phase or the doctor failed, 2 needs a
// terminal, 130 cancelled or stopped (ux-spec §3.1).
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	tea "charm.land/bubbletea/v2"

	"github.com/Robertcl795/umbra-bootstrapper/internal/app"
	"github.com/Robertcl795/umbra-bootstrapper/internal/effects"
	"github.com/Robertcl795/umbra-bootstrapper/internal/i18n"
	"github.com/Robertcl795/umbra-bootstrapper/internal/screens"
	"github.com/Robertcl795/umbra-bootstrapper/internal/sys"
)

// version is set at release time (-ldflags "-X main.version=…").
var version = "0.0.0-dev"

func main() { os.Exit(run()) }

func run() int {
	envFlag := flag.String("env-dir", "", "the bootstrapper's env/wsl directory")
	showVersion := flag.Bool("version", false, "print the version and exit")
	resume := flag.Bool("resume", false, "run stage 2 with the staged selection (umbra bootstrap resume)")
	flag.Parse()
	if *showVersion {
		fmt.Println("umbra-setup " + version + " (Umbra bootstrapper)")
		return 0
	}
	tr := i18n.New(i18n.Resolve(os.Getenv))
	if !effects.StdinTTY() || !effects.StdoutTTY() {
		fmt.Fprintln(os.Stderr, tr("err.notty"))
		return 2
	}
	envDir, _ := filepath.Abs(effects.EnvDir(*envFlag))
	env := effects.FromOS(envDir, version)
	init := append(effects.Scan(env), effects.ReadCatalog(envDir), effects.Stored)
	init = append(init, effects.ScanSlow(env)...)
	if env.Root && !*resume {
		init = append(init, effects.Users)
	}
	cmds := app.Cmds{
		Init:         init,
		Glitch:       effects.GlitchTick,
		Shine:        effects.ShineTick,
		Tick:         effects.Tick,
		SudoValidate: effects.SudoValidate,
		SudoRefresh:  effects.SudoRefresh,
		Start:        func(args []string, pw string) tea.Cmd { return effects.Start(envDir, args, pw) },
		Wait:         effects.Wait,
		ReadEvents:   effects.ReadEvents,
		Stop:         effects.Stop,
		Doctor:       func(log string, env []string) tea.Cmd { return effects.Doctor(envDir, log, env) },
		LogTail:      func(p string) tea.Cmd { return effects.LogTail(p, 10) },
	}
	if *resume {
		cmds.Start = func(args []string, pw string) tea.Cmd {
			return effects.StartScript(effects.Resumer(envDir), envDir, args, pw)
		}
		cmds.Doctor = nil // finish.sh runs it as the last phase
	}
	model := app.New(env, cmds, effects.Pending()...)
	if *resume {
		model = model.Resuming(sys.ResumeFrom(os.Getenv))
	}
	final, err := tea.NewProgram(model).Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, "umbra-setup:", err)
		return 1
	}
	res := final.(app.Model).Result()
	switch res.Action {
	case screens.DryRun:
		// The plan as install.sh sees it, printed to the terminal after the TUI closed.
		cmd := exec.Command("bash", append([]string{filepath.Join(envDir, "..", "..", "install.sh"), "--dry-run"}, res.Args...)...)
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
		if err := cmd.Run(); err != nil {
			return 1
		}
		return 0
	case screens.Quit:
		fmt.Println(tr("cancelled"))
	case screens.Leave:
		// Stage 1 is done: terminate the distro so PowerShell is back and the next start is the
		// new user. Without interop, the restart screen's commands, printed.
		distro := env.Distro
		next := tr("leave.next", "cmd", "wsl.exe -d "+distro)
		if !effects.LeaveWSL(distro, os.Stdout, tr("leave.closing", "distro", distro), next) {
			fmt.Println(tr("leave.manual"))
			fmt.Println("  wsl.exe --terminate " + distro)
			fmt.Println("  " + next)
		}
	}
	return res.Code
}
