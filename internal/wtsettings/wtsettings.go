// Package wtsettings reads Windows Terminal's settings.json and changes its defaultProfile, and
// nothing else (ADR 0043 as amended for Make default: the user confirms on the screen, the file
// is backed up first). It is pure: bytes in, bytes out; the caller reads and writes the file.
package wtsettings

import (
	"encoding/json"
	"errors"
	"regexp"
	"strings"
)

// PowerShellCore is the source of the profile Windows Terminal generates for PowerShell 7.
const PowerShellCore = "Windows.Terminal.PowershellCore"

// Status is what the file says: the default profile's guid and the guid of the visible profile
// with the asked source ("" when there is none yet: Windows Terminal adds it when it starts).
type Status struct {
	Default string
	Profile string
}

// IsDefault reports whether that profile is the default.
func (s Status) IsDefault() bool { return s.Profile != "" && strings.EqualFold(s.Default, s.Profile) }

// Strip turns Windows Terminal's JSON with comments into JSON: // and /* */ comments outside
// strings become spaces, and a comma before } or ] is dropped.
func Strip(b []byte) []byte {
	out := make([]byte, 0, len(b))
	inStr, esc := false, false
	for i := 0; i < len(b); i++ {
		c := b[i]
		switch {
		case inStr:
			out = append(out, c)
			switch {
			case esc:
				esc = false
			case c == '\\':
				esc = true
			case c == '"':
				inStr = false
			}
		case c == '"':
			inStr = true
			out = append(out, c)
		case c == '/' && i+1 < len(b) && b[i+1] == '/':
			for i < len(b) && b[i] != '\n' {
				i++
			}
			if i < len(b) {
				out = append(out, '\n')
			}
		case c == '/' && i+1 < len(b) && b[i+1] == '*':
			i += 2
			for i+1 < len(b) && (b[i] != '*' || b[i+1] != '/') {
				i++
			}
			i++
			out = append(out, ' ')
		case c == '}' || c == ']':
			// drop a trailing comma: the last non-space byte written
			j := len(out) - 1
			for j >= 0 && (out[j] == ' ' || out[j] == '\n' || out[j] == '\r' || out[j] == '\t') {
				j--
			}
			if j >= 0 && out[j] == ',' {
				out = append(out[:j], out[j+1:]...)
			}
			out = append(out, c)
		default:
			out = append(out, c)
		}
	}
	return out
}

type file struct {
	DefaultProfile *string `json:"defaultProfile"`
	Profiles       struct {
		List []struct {
			GUID   string `json:"guid"`
			Source string `json:"source"`
			Hidden bool   `json:"hidden"`
		} `json:"list"`
	} `json:"profiles"`
}

func parse(b []byte) (file, error) {
	var f file
	if err := json.Unmarshal(Strip(b), &f); err != nil {
		return file{}, errors.New("settings.json is not valid JSON: " + err.Error())
	}
	return f, nil
}

// Read returns the default profile and the first visible profile with source.
func Read(b []byte, source string) (Status, error) {
	f, err := parse(b)
	if err != nil {
		return Status{}, err
	}
	var st Status
	if f.DefaultProfile != nil {
		st.Default = *f.DefaultProfile
	}
	for _, p := range f.Profiles.List {
		if p.Source == source && !p.Hidden {
			st.Profile = p.GUID
			break
		}
	}
	return st, nil
}

var (
	defaultKey = regexp.MustCompile(`"defaultProfile"\s*:\s*"[^"]*"`)
	guidRe     = regexp.MustCompile(`^\{[0-9A-Fa-f-]{36}\}$`)
)

// SetDefault returns the file with the top-level defaultProfile set to guid. Only that value
// changes. It refuses a file that is not JSON, one without a top-level defaultProfile, or one
// where the first such key is not the top-level one.
func SetDefault(b []byte, guid string) ([]byte, error) {
	if !guidRe.MatchString(guid) {
		return nil, errors.New("not a profile guid: " + guid)
	}
	f, err := parse(b)
	if err != nil {
		return nil, err
	}
	if f.DefaultProfile == nil {
		return nil, errors.New("settings.json has no top-level defaultProfile")
	}
	loc := defaultKey.FindIndex(b)
	if loc == nil {
		return nil, errors.New("settings.json: defaultProfile not found")
	}
	out := append(append(append([]byte{}, b[:loc[0]]...), []byte(`"defaultProfile": "`+guid+`"`)...), b[loc[1]:]...)
	// The change must be exactly the top-level value: read it back.
	g, err := parse(out)
	if err != nil || g.DefaultProfile == nil || *g.DefaultProfile != guid {
		return nil, errors.New("settings.json: the first defaultProfile is not the top-level one")
	}
	return out, nil
}
