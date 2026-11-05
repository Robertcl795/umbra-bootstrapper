// Package msgs holds every message the umbra-setup program passes (ux-spec §2.2). Messages are
// named structs, never strings (Elm rule E3). Effects send them; the app and screens read them.
package msgs

import "github.com/Robertcl795/umbra-bootstrapper/internal/catalog"

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

// Catalog carries the component catalog once it is read.
type Catalog struct{ Cat catalog.Catalog }

// CatalogErr says the catalog could not be read or parsed.
type CatalogErr struct{ Err string }

// GlitchTick advances the boot glitch by one frame.
type GlitchTick struct{ Frame int }
