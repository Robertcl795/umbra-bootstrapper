// Command umbra-setup is the bootstrapper's TUI and Umbra's entry point (ADR 0037).
//
// It walks scan → profile → components → theme → review, then runs install.sh with the flags of
// the review's "Next time" line and follows its phases (ADR 0040), then the doctor.
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
)

// version is set at release time (-ldflags "-X main.version=…").
var version = "0.0.0-dev"

func main() { os.Exit(run()) }

func run() int {
	envFlag := flag.String("env-dir", "", "the bootstrapper's env/wsl directory")
	showVersion := flag.Bool("version", false, "print the version and exit")
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
	cmds := app.Cmds{
		Init:         init,
		Glitch:       effects.GlitchTick,
		Tick:         effects.Tick,
		SudoValidate: effects.SudoValidate,
		SudoRefresh:  effects.SudoRefresh,
		Start:        func(args []string) tea.Cmd { return effects.Start(envDir, args) },
		Wait:         effects.Wait,
		ReadEvents:   effects.ReadEvents,
		Stop:         effects.Stop,
		Doctor:       func(log string) tea.Cmd { return effects.Doctor(envDir, log) },
		LogTail:      func(p string) tea.Cmd { return effects.LogTail(p, 10) },
	}
	final, err := tea.NewProgram(app.New(env, cmds, effects.Pending()...)).Run()
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
	}
	return res.Code
}
