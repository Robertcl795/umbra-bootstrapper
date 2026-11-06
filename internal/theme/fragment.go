package theme

import (
	"encoding/json"
	"errors"
)

// NerdFont is the brand mono font (brand/README.md: JetBrains Mono) as its Nerd Font family name
// in Windows. verify at G-B2/G-B3 against the installed font; fragments do not document
// `font.face` (ADR 0043).
const NerdFont = "JetBrainsMono Nerd Font"

// Scheme is a Windows Terminal color scheme, in the field order of the generated files.
type Scheme struct {
	Name                string `json:"name"`
	Background          string `json:"background"`
	Foreground          string `json:"foreground"`
	CursorColor         string `json:"cursorColor"`
	SelectionBackground string `json:"selectionBackground"`
	Black               string `json:"black"`
	Red                 string `json:"red"`
	Green               string `json:"green"`
	Yellow              string `json:"yellow"`
	Blue                string `json:"blue"`
	Purple              string `json:"purple"`
	Cyan                string `json:"cyan"`
	White               string `json:"white"`
	BrightBlack         string `json:"brightBlack"`
	BrightRed           string `json:"brightRed"`
	BrightGreen         string `json:"brightGreen"`
	BrightYellow        string `json:"brightYellow"`
	BrightBlue          string `json:"brightBlue"`
	BrightPurple        string `json:"brightPurple"`
	BrightCyan          string `json:"brightCyan"`
	BrightWhite         string `json:"brightWhite"`
}

// SchemeName is the scheme's name in Windows Terminal.
func SchemeName(variant string) string {
	return map[string]string{"umbra": "Umbra", "void": "Umbra Void", "lux": "Umbra Lux"}[variant]
}

// WTScheme builds a variant's scheme from the generated roles and ANSI table; it equals
// themes/terminals/windows-terminal/<variant>.json (a test checks it).
func WTScheme(variant string) Scheme {
	r, a := Roles[variant], ANSI[variant]
	return Scheme{
		Name: SchemeName(variant), Background: r["bg"], Foreground: r["fg"],
		CursorColor: r["cursor"], SelectionBackground: r["selection"],
		Black: a[0], Red: a[1], Green: a[2], Yellow: a[3], Blue: a[4], Purple: a[5], Cyan: a[6], White: a[7],
		BrightBlack: a[8], BrightRed: a[9], BrightGreen: a[10], BrightYellow: a[11],
		BrightBlue: a[12], BrightPurple: a[13], BrightCyan: a[14], BrightWhite: a[15],
	}
}

type wtFont struct {
	Face string `json:"face"`
}

type wtProfile struct {
	Name        string `json:"name"`
	Commandline string `json:"commandline"`
	ColorScheme string `json:"colorScheme"`
	Font        wtFont `json:"font"`
}

type wtFragment struct {
	Profiles []wtProfile `json:"profiles"`
	Schemes  []Scheme    `json:"schemes"`
}

// Fragment is the Windows Terminal fragment (ADR 0043): the three Umbra schemes and one profile
// of its own, "Umbra · <distro>", in the chosen variant. It updates no other profile.
func Fragment(distro, variant, font string) ([]byte, error) {
	if distro == "" {
		return nil, errors.New("fragment: no distro")
	}
	if _, ok := Roles[variant]; !ok {
		return nil, errors.New("fragment: unknown variant " + variant)
	}
	f := wtFragment{Profiles: []wtProfile{{
		Name:        "Umbra · " + distro,
		Commandline: "wsl.exe -d " + distro + " --cd ~",
		ColorScheme: SchemeName(variant),
		Font:        wtFont{Face: font},
	}}}
	for _, v := range Variants {
		f.Schemes = append(f.Schemes, WTScheme(v))
	}
	b, err := json.MarshalIndent(f, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(b, '\n'), nil
}
