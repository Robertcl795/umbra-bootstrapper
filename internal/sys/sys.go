// Package sys describes the machine umbra-setup runs on. It is pure: detection takes the
// environment and a file reader as functions, so effects passes the real ones and tests pass
// fixtures (Elm rule E5).
package sys

import (
	"strings"

	"github.com/Robertcl795/umbra-bootstrapper/internal/msgs"
	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
)

// Env is everything the screens may know about the machine.
type Env struct {
	Platform string // wsl-ubuntu, wsl-arch, ubuntu, arch, omarchy; "" when unsupported
	User     string
	Root     bool
	Desktop  bool  // a graphical session runs
	Access   *bool // Umbra AI access; nil = not checked
	Terminal string
	Lang     string
	Theme    theme.T
	ThemeBad string // an unknown UM_THEME value, for one warning
	NoMotion bool   // no glitch: NO_COLOR, no TTY, TERM=dumb or UM_REDUCED_MOTION=1
	EnvDir   string // the bootstrapper's env/wsl
	Version  string
	Distro   string // WSL_DISTRO_NAME, for the restart commands
	ThemeSet bool   // UM_THEME was given: it wins over the stored theme of a re-run
}

// Platform mirrors um_platform in selector.sh: UM_OS and UM_IS_WSL override the detection.
func Platform(get func(string) string, read func(string) (string, bool)) string {
	id := get("UM_OS")
	if id == "" {
		if s, ok := read("/etc/os-release"); ok {
			id = osReleaseID(s)
		}
	}
	wsl := false
	switch get("UM_IS_WSL") {
	case "1":
		wsl = true
	case "0":
	default:
		if _, ok := read("/proc/sys/fs/binfmt_misc/WSLInterop"); ok {
			wsl = true
		} else if v, ok := read("/proc/version"); ok && strings.Contains(strings.ToLower(v), "microsoft") {
			wsl = true
		}
	}
	switch id {
	case "omarchy":
		return "omarchy"
	case "ubuntu", "arch":
		if wsl {
			return "wsl-" + id
		}
		return id
	}
	return ""
}

func osReleaseID(s string) string {
	for _, line := range strings.Split(s, "\n") {
		if v, ok := strings.CutPrefix(line, "ID="); ok {
			return strings.Trim(v, `"'`)
		}
	}
	return ""
}

// DesktopSession mirrors desktop_session in selector.sh.
func DesktopSession(get func(string) string) bool {
	return get("XDG_CURRENT_DESKTOP") != "" || get("WAYLAND_DISPLAY") != "" || get("DISPLAY") != ""
}

// AccessOverride reads UM_AI_ACCESS=0|1 (the same override selector.sh honors).
func AccessOverride(get func(string) string) *bool {
	switch get("UM_AI_ACCESS") {
	case "1":
		v := true
		return &v
	case "0":
		v := false
		return &v
	}
	return nil
}

// Terminal names the terminal for the scan.
func Terminal(get func(string) string) string {
	switch {
	case get("WT_SESSION") != "":
		return "Windows Terminal"
	case get("TERM_PROGRAM") != "":
		return get("TERM_PROGRAM")
	case get("TERM") != "":
		return get("TERM")
	}
	return "unknown"
}

// NoMotion reports whether animations are off (ux-spec §6.3).
func NoMotion(get func(string) string, p theme.Profile) bool {
	return p == theme.None || get("UM_REDUCED_MOTION") == "1"
}

// ParseStored reads profile, theme and components from the [data] table of chezmoi's config, as
// .chezmoi.toml.tmpl writes it (one `key = "value"` per line).
func ParseStored(text string) msgs.Stored {
	var st msgs.Stored
	inData := false
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "[") {
			inData = line == "[data]"
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !inData || !ok {
			continue
		}
		v = strings.Trim(strings.TrimSpace(v), `"`)
		switch strings.TrimSpace(k) {
		case "profile":
			st.Profile, st.Found = v, true
		case "theme":
			st.Theme = v
		case "components":
			if v != "" {
				st.Components = strings.Split(v, ",")
			}
		}
	}
	return st
}
