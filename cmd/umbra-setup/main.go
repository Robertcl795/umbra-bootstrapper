// Command umbra-setup is the bootstrapper's TUI and Umbra's entry point (ADR 0037).
//
// G3 build: it walks scan → profile → components → theme → review and prints the install.sh
// command that does what was picked; running bootstrap.sh from the TUI arrives in G4.
//
// Exit codes: 0 done, 1 error, 2 needs a terminal, 130 cancelled (ux-spec §3.1).
package main

import (
	"flag"
	"fmt"
	"os"

	tea "charm.land/bubbletea/v2"

	"github.com/Robertcl795/umbra-bootstrapper/internal/app"
	"github.com/Robertcl795/umbra-bootstrapper/internal/effects"
	"github.com/Robertcl795/umbra-bootstrapper/internal/i18n"
	"github.com/Robertcl795/umbra-bootstrapper/internal/plan"
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
	envDir := effects.EnvDir(*envFlag)
	env := effects.FromOS(envDir, version)
	m := app.New(env, app.Cmds{Init: append(effects.Scan(env), effects.ReadCatalog(envDir)), Glitch: effects.GlitchTick})
	final, err := tea.NewProgram(m).Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, "umbra-setup:", err)
		return 1
	}
	res := final.(app.Model).Result()
	switch res.Action {
	case screens.Install, screens.DryRun:
		args := res.Args
		if res.Action == screens.DryRun {
			args = append([]string{"--dry-run"}, args...)
		}
		fmt.Println(tr("preview"))
		fmt.Println("  " + plan.Command(args))
		return 0
	default:
		fmt.Println(tr("cancelled"))
		return 130
	}
}
