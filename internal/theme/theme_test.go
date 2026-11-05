package theme

import (
	"strings"
	"testing"
)

func env(kv ...string) func(string) string {
	m := map[string]string{}
	for i := 0; i+1 < len(kv); i += 2 {
		m[kv[i]] = kv[i+1]
	}
	return func(k string) string { return m[k] }
}

func TestDetect(t *testing.T) {
	cases := []struct {
		name string
		get  func(string) string
		tty  bool
		want Profile
	}{
		{"no tty", env("COLORTERM", "truecolor"), false, None},
		{"NO_COLOR", env("NO_COLOR", "1", "COLORTERM", "truecolor"), true, None},
		{"dumb", env("TERM", "dumb", "COLORTERM", "truecolor"), true, None},
		{"truecolor", env("COLORTERM", "24bit"), true, TrueColor},
		{"windows terminal", env("WT_SESSION", "x"), true, TrueColor},
		{"plain", env(), true, ANSI16},
	}
	for _, tc := range cases {
		if got := Detect(tc.get, tc.tty); got != tc.want {
			t.Errorf("%s: %v, want %v", tc.name, got, tc.want)
		}
	}
}

func TestVariant(t *testing.T) {
	cases := []struct {
		um, fgbg, want string
		ok             bool
	}{
		{"void", "", "void", true}, {"neon", "", "umbra", false},
		{"", "0;15", "lux", true}, {"", "15;0", "umbra", true}, {"", "", "umbra", true},
	}
	for _, tc := range cases {
		if got, ok := Variant(tc.um, tc.fgbg); got != tc.want || ok != tc.ok {
			t.Errorf("Variant(%q, %q) = %q, %v", tc.um, tc.fgbg, got, ok)
		}
	}
}

func TestNoColorWritesNoEscapes(t *testing.T) {
	th := New("umbra", None)
	for _, s := range []string{th.R("accent", "x"), th.B("error", "x"), th.Selected().Render("x"), th.Swatch("lux", "ok")} {
		if strings.Contains(s, "\x1b[") {
			t.Errorf("escape code without color: %q", s)
		}
	}
	if th.BorderGrid(4, 3) != nil || th.Corona(5) != nil || th.Background() != nil {
		t.Error("gradients or background without truecolor")
	}
}

func TestTrueColorUsesTheRoleHex(t *testing.T) {
	for _, v := range Variants {
		got := New(v, TrueColor).R("error", "x")
		hex := Roles[v]["error"]
		want := "38;2;" + rgb(hex)
		if !strings.Contains(got, want) {
			t.Errorf("%s: %q lacks %s", v, got, want)
		}
	}
}

func TestANSI16UsesBasicSlots(t *testing.T) {
	if got := New("umbra", ANSI16).R("error", "x"); !strings.Contains(got, "\x1b[31m") {
		t.Errorf("error in ANSI-16: %q, want SGR 31", got)
	}
}

func TestGradients(t *testing.T) {
	g := New("umbra", TrueColor).BorderGrid(10, 4)
	if len(g) != 40 {
		t.Fatalf("grid size %d", len(g))
	}
	// 45°: bottom-left is the first stop (ultraviolet), top-right the last (plasma).
	// The blend may stop short of the last stop in a non-square box, so compare distances.
	uv, pl := unhexColor(Gradients["activeBorder"][0]), unhexColor(Gradients["activeBorder"][1])
	if hexOf(g[30]) != Gradients["activeBorder"][0] || dist(g[9], pl) >= dist(g[9], uv) {
		t.Errorf("corners: bottom-left %s, top-right %s", hexOf(g[30]), hexOf(g[9]))
	}
	c := New("lux", TrueColor).Corona(3)
	if hexOf(c[0]) != Roles["lux"]["accent"] || hexOf(c[2]) != Roles["lux"]["warn"] {
		t.Errorf("lux corona built from roles: %s … %s", hexOf(c[0]), hexOf(c[2]))
	}
}

func rgb(hex string) string {
	var r, g, b int
	for i, p := range []*int{&r, &g, &b} {
		*p = unhex(hex[1+2*i : 3+2*i])
	}
	return itoa(r) + ";" + itoa(g) + ";" + itoa(b)
}

func unhex(s string) int {
	n := 0
	for _, c := range strings.ToLower(s) {
		n *= 16
		if c >= 'a' {
			n += int(c-'a') + 10
		} else {
			n += int(c - '0')
		}
	}
	return n
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	s := ""
	for n > 0 {
		s = string(rune('0'+n%10)) + s
		n /= 10
	}
	return s
}

func hexOf(c interface{ RGBA() (r, g, b, a uint32) }) string {
	r, g, b, _ := c.RGBA()
	const digits = "0123456789ABCDEF"
	out := "#"
	for _, v := range []uint32{r >> 8, g >> 8, b >> 8} {
		out += string(digits[v>>4]) + string(digits[v&15])
	}
	return out
}

type rgbc struct{ r, g, b uint32 }

func (c rgbc) RGBA() (uint32, uint32, uint32, uint32) { return c.r << 8, c.g << 8, c.b << 8, 0xffff }

func unhexColor(h string) rgbc {
	return rgbc{uint32(unhex(h[1:3])), uint32(unhex(h[3:5])), uint32(unhex(h[5:7]))}
}

func dist(a, b interface{ RGBA() (r, g, b, a uint32) }) int {
	ar, ag, ab, _ := a.RGBA()
	br, bg, bb, _ := b.RGBA()
	d := func(x, y uint32) int { v := int(x>>8) - int(y>>8); return v * v }
	return d(ar, br) + d(ag, bg) + d(ab, bb)
}
