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
	Driver   string // UM_DRIVER: "ps1" when install.ps1 drives both stages (ADR 0042)
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

// RegularUsers lists the users with uid 1000–65533 in /etc/passwd text, as regular_users in
// stage1.sh does with getent.
func RegularUsers(passwd string) []string {
	var out []string
	for _, line := range strings.Split(passwd, "\n") {
		f := strings.Split(line, ":")
		if len(f) < 3 {
			continue
		}
		uid := 0
		for _, r := range f[2] {
			if r < '0' || r > '9' {
				uid = -1
				break
			}
			uid = uid*10 + int(r-'0')
		}
		if uid >= 1000 && uid < 65534 {
			out = append(out, f[0])
		}
	}
	return out
}

// ValidUsername is stage1.sh's valid_username: ^[a-z_][a-z0-9_-]{0,31}$.
func ValidUsername(u string) bool {
	if len(u) == 0 || len(u) > 32 {
		return false
	}
	for i, r := range u {
		switch {
		case r >= 'a' && r <= 'z', r == '_':
		case i > 0 && (r >= '0' && r <= '9' || r == '-'):
		default:
			return false
		}
	}
	return true
}

// Resume is the selection stage 1 staged for stage 2 (bootstrap.env, which `umbra bootstrap
// resume` exports before it starts umbra-setup --resume).
type Resume struct {
	Components []string
	Skip       []string
	Profile    string
}

// ResumeFrom reads it from the environment: UM_COMPONENTS, UM_SKIP and UM_MODE (personal when
// unset, as bootstrap.sh does).
func ResumeFrom(get func(string) string) Resume {
	r := Resume{Components: list(get("UM_COMPONENTS")), Skip: list(get("UM_SKIP")), Profile: get("UM_MODE")}
	if r.Profile == "" {
		r.Profile = "personal"
	}
	return r
}

func list(s string) []string {
	var out []string
	for _, f := range strings.Split(s, ",") {
		if f = strings.TrimSpace(f); f != "" {
			out = append(out, f)
		}
	}
	return out
}
