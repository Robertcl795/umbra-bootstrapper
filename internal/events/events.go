// Package events parses the phase event stream of ADR 0040:
// "v1<TAB>timestamp<TAB>kind<TAB>phase<TAB>state<TAB>message", one event per line.
// It is pure; reading the FIFO is an effect.
package events

import (
	"errors"
	"fmt"
	"strings"
	"time"
)

// ErrUnknownVersion is returned for a line of a later version; readers skip such lines.
var ErrUnknownVersion = errors.New("events: unknown version")

// Event is one parsed line.
type Event struct {
	At      time.Time
	Kind    string // phase or log
	Phase   string // "" when the line carries "-"
	State   string // phase: start, ok, fail, skip; log: info, warn, error
	Message string
}

var states = map[string]map[string]bool{
	"phase": {"start": true, "ok": true, "fail": true, "skip": true},
	"log":   {"info": true, "warn": true, "error": true},
}

// Parse reads one line, with or without its trailing newline.
func Parse(line string) (Event, error) {
	line = strings.TrimRight(line, "\r\n")
	f := strings.SplitN(line, "\t", 6)
	if len(f) == 0 || f[0] != "v1" {
		if len(f) > 0 && strings.HasPrefix(f[0], "v") {
			return Event{}, ErrUnknownVersion
		}
		return Event{}, fmt.Errorf("events: not an event line: %q", line)
	}
	if len(f) != 6 {
		return Event{}, fmt.Errorf("events: want 6 fields, got %d: %q", len(f), line)
	}
	at, err := time.Parse("2006-01-02T15:04:05.000Z07:00", f[1])
	if err != nil {
		return Event{}, fmt.Errorf("events: bad timestamp %q: %w", f[1], err)
	}
	kind, phase, state := f[2], f[3], f[4]
	ok, known := states[kind]
	if !known {
		return Event{}, fmt.Errorf("events: unknown kind %q", kind)
	}
	if !ok[state] {
		return Event{}, fmt.Errorf("events: unknown state %q for %s", state, kind)
	}
	if phase == "-" {
		phase = ""
	}
	return Event{At: at.UTC(), Kind: kind, Phase: phase, State: state, Message: strings.ToValidUTF8(f[5], "�")}, nil
}
