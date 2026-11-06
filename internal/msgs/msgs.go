// Package msgs holds every message the umbra-setup program passes (ux-spec §2.2). Messages are
// named structs, never strings (Elm rule E3). Effects send them; the app and screens read them.
package msgs

import (
	"time"

	"github.com/Robertcl795/umbra-bootstrapper/internal/catalog"
	"github.com/Robertcl795/umbra-bootstrapper/internal/events"
)

// FactState is how a scan line is drawn.
type FactState int

const (
	FactOK      FactState = iota // [ OK ]
	FactNA                       // [ -- ]
	FactPending                  // [ ⠋  ] spinner
	FactBad                      // [ !! ]
)

// ScanFact is one line of the system scan.
type ScanFact struct {
	Key      string // i18n key of the label (scan.platform, …)
	Value    string // shown as is
	ValueKey string // i18n key shown after Value ("Value · text"), or alone
	State    FactState
}

// Catalog carries the component catalog and its package table once they are read.
type Catalog struct {
	Cat  catalog.Catalog
	Pkgs catalog.Packages // empty when packages.tsv is missing (an older checkout)
}

// CatalogErr says the catalog could not be read or parsed.
type CatalogErr struct{ Err string }

// GlitchTick advances the boot glitch by one frame.
type GlitchTick struct{ Frame int }

// ShineTick moves the corona sweep over the wordmark: frames 1..ui.ShineFrames draw the band,
// any later frame is the rest between sweeps (ux-spec §6.3).
type ShineTick struct{ Frame int }

// Access is the result of the Umbra AI access check (umbra_ai_access in selector.sh).
type Access struct{ OK bool }

// Sudo is the result of `sudo -n true` during the scan: Passwordless or not.
type Sudo struct{ Passwordless bool }

// Stored is the selection a previous run left in chezmoi's data (re-run, ux-spec §2.2).
type Stored struct {
	Found      bool
	Profile    string
	Theme      string
	Components []string

	SkipPackages []string // packages.tsv rows left out (skip_packages)
	Shell        string   // zsh, fish
}

// DefaultStatus is what is the default now (install/shell/default.sh --status): the login
// shell, and on WSL Windows Terminal's default profile and its PowerShell 7 profile ("" when it
// lists none yet).
type DefaultStatus struct {
	Login, WTSettings, WTDefault, WTPwsh7 string
	Err                                   string
}

// DefaultDone carries what Make default changed (default.sh's messages), or why it could not.
type DefaultDone struct {
	Lines []string
	Err   string
}

// Tick drives spinners and elapsed times while something runs (no tick at rest).
type Tick struct{ Now time.Time }

// SudoReady says sudo has a fresh timestamp (or is not needed); SudoFailed says why not.
type (
	SudoReady  struct{}
	SudoFailed struct{ Err string }
)

// RunStarted carries the child's process id and the files of this run.
type RunStarted struct {
	PID    int
	Log    string
	Events string
	Stop   string // create this file to stop between phases
}

// RunErr says the run could not start.
type RunErr struct{ Err string }

// EventsRead carries the events found since the last read and the next offset.
type EventsRead struct {
	Events []events.Event
	Offset int64
}

// RunExited is the child's exit code.
type RunExited struct{ Code int }

// DoctorDone is the result of tests/99_smoke.sh; Tail is its last lines.
type DoctorDone struct {
	OK   bool
	Tail []string
}

// LogTail carries the last lines of the run's log file (failed screen).
type LogTail struct{ Lines []string }

// Batch is several messages from one effect; the app applies them in order.
type Batch []any

// SudoRefreshed says the 60 s sudo refresh ran.
type SudoRefreshed struct{}

// Users are the regular users of the machine (uid 1000–65533), read when running as root.
type Users struct{ Names []string }
