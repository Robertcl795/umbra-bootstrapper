package sys

import (
	"strings"
	"testing"

	"github.com/Robertcl795/umbra-bootstrapper/internal/theme"
)

func getter(m map[string]string) func(string) string { return func(k string) string { return m[k] } }

func files(m map[string]string) func(string) (string, bool) {
	return func(p string) (string, bool) { v, ok := m[p]; return v, ok }
}

func TestPlatform(t *testing.T) {
	cases := []struct {
		name string
		env  map[string]string
		fs   map[string]string
		want string
	}{
		{"override wsl ubuntu", map[string]string{"UM_OS": "ubuntu", "UM_IS_WSL": "1"}, nil, "wsl-ubuntu"},
		{"override native arch", map[string]string{"UM_OS": "arch", "UM_IS_WSL": "0"}, map[string]string{"/proc/version": "Microsoft"}, "arch"},
		{"os-release + WSLInterop", nil, map[string]string{"/etc/os-release": "NAME=\"Arch\"\nID=arch\n", "/proc/sys/fs/binfmt_misc/WSLInterop": ""}, "wsl-arch"},
		{"proc/version microsoft", nil, map[string]string{"/etc/os-release": "ID=\"ubuntu\"\n", "/proc/version": "Linux 6.18-microsoft-standard-WSL2"}, "wsl-ubuntu"},
		{"omarchy", map[string]string{"UM_OS": "omarchy"}, nil, "omarchy"},
		{"unsupported", nil, map[string]string{"/etc/os-release": "ID=fedora\n"}, ""},
	}
	for _, tc := range cases {
		if got := Platform(getter(tc.env), files(tc.fs)); got != tc.want {
			t.Errorf("%s: %q, want %q", tc.name, got, tc.want)
		}
	}
}

func TestSmallDetectors(t *testing.T) {
	if !DesktopSession(getter(map[string]string{"WAYLAND_DISPLAY": "wayland-0"})) || DesktopSession(getter(nil)) {
		t.Error("DesktopSession")
	}
	if a := AccessOverride(getter(map[string]string{"UM_AI_ACCESS": "1"})); a == nil || !*a {
		t.Error("AccessOverride 1")
	}
	if AccessOverride(getter(nil)) != nil {
		t.Error("AccessOverride unset")
	}
	if Terminal(getter(map[string]string{"WT_SESSION": "x", "TERM": "xterm"})) != "Windows Terminal" {
		t.Error("Terminal")
	}
	if !NoMotion(getter(nil), theme.None) || !NoMotion(getter(map[string]string{"UM_REDUCED_MOTION": "1"}), theme.TrueColor) || NoMotion(getter(nil), theme.TrueColor) {
		t.Error("NoMotion")
	}
}

func TestRegularUsersAndNames(t *testing.T) {
	got := RegularUsers("root:x:0:0::/root:/bin/bash\nnobody:x:65534:65534::/:/usr/bin/nologin\numbra:x:1000:1000::/home/umbra:/bin/bash\nbad\n")
	if len(got) != 1 || got[0] != "umbra" {
		t.Errorf("RegularUsers: %v", got)
	}
	for u, want := range map[string]bool{"umbra": true, "_x": true, "a-1": true, "1a": false, "Umbra": false, "": false, "a b": false, "-a": false} {
		if ValidUsername(u) != want {
			t.Errorf("ValidUsername(%q) != %v", u, want)
		}
	}
}

func TestParseStored(t *testing.T) {
	text := "sourceDir = \"/x\"\n\n[data]\n    profile = \"work\"\n    theme = \"lux\"\n    components = \"packages,shell\"\n    skip_packages = \"eza,fzf\"\n"
	st := ParseStored(text)
	if !st.Found || st.Profile != "work" || st.Theme != "lux" || strings.Join(st.Components, ",") != "packages,shell" {
		t.Errorf("%+v", st)
	}
	if strings.Join(st.SkipPackages, ",") != "eza,fzf" {
		t.Errorf("skip_packages: %v", st.SkipPackages)
	}
	if st := ParseStored("[data]\n    profile = \"personal\"\n    skip_packages = \"\"\n"); st.SkipPackages != nil {
		t.Errorf("empty skip_packages: %v", st.SkipPackages)
	}
}
