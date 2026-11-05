// Package i18n holds umbra-setup's messages in English and Spanish (ADR 0037, as ADR 0033).
package i18n

import (
	"embed"
	"encoding/json"
	"strings"
)

//go:embed en.json es.json
var files embed.FS

// Langs are the supported languages.
var Langs = []string{"en", "es"}

// Resolve picks the language: UM_LANG (en|es), then the first non-empty of LC_ALL, LC_MESSAGES,
// LANG; a value starting with "es" gives Spanish, anything else English.
func Resolve(get func(string) string) string {
	if v := get("UM_LANG"); v == "en" || v == "es" {
		return v
	}
	for _, k := range []string{"LC_ALL", "LC_MESSAGES", "LANG"} {
		if v := get(k); v != "" {
			if strings.HasPrefix(v, "es") {
				return "es"
			}
			return "en"
		}
	}
	return "en"
}

// Catalog returns one language's messages.
func Catalog(lang string) map[string]string {
	b, err := files.ReadFile(lang + ".json")
	if err != nil {
		b, _ = files.ReadFile("en.json")
	}
	m := map[string]string{}
	_ = json.Unmarshal(b, &m)
	return m
}

// Func looks up a key and fills {name} placeholders from name/value pairs.
type Func func(key string, kv ...string) string

// New returns the lookup for a language. A missing key comes back as the key itself, so a test
// can find it in rendered output.
func New(lang string) Func {
	m := Catalog(lang)
	return func(key string, kv ...string) string {
		s, ok := m[key]
		if !ok {
			return key
		}
		for i := 0; i+1 < len(kv); i += 2 {
			s = strings.ReplaceAll(s, "{"+kv[i]+"}", kv[i+1])
		}
		return s
	}
}
