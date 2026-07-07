package clientsignals

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

type markerFixture struct {
	Agent  string   `json:"agent"`
	Env    string   `json:"env"`
	Kind   string   `json:"kind"`
	Values []string `json:"values"`
}

type sanitizeFixture struct {
	Name  string `json:"name"`
	Input string `json:"input"`
	Want  string `json:"want"`
	Valid bool   `json:"valid"`
}

type parentFixture struct {
	Raw  string `json:"raw"`
	Want string `json:"want"`
}

type headerFixture struct {
	Name            string            `json:"name"`
	Prefix          string            `json:"prefix"`
	Signals         fixtureSignals    `json:"signals"`
	Headers         map[string]string `json:"headers"`
	UserAgentSuffix string            `json:"userAgentSuffix"`
}

type fixtureSignals struct {
	Interactive bool   `json:"interactive"`
	Parent      string `json:"parent"`
	Agent       string `json:"agent"`
	AgentSource string `json:"agentSource"`
	CI          bool   `json:"ci"`
}

func TestKnownMarkers_MatchSharedSpec(t *testing.T) {
	var fixtures []markerFixture
	readSpecFixture(t, "markers.json", &fixtures)

	if len(fixtures) != len(knownMarkers) {
		t.Fatalf("marker count = %d, want %d", len(knownMarkers), len(fixtures))
	}

	for i, fixture := range fixtures {
		got := knownMarkers[i]
		if got.agent != fixture.Agent || got.env != fixture.Env || matchKindName(got.kind) != fixture.Kind {
			t.Fatalf("marker %d = %+v, want %+v", i, got, fixture)
		}
		if len(got.values) != len(fixture.Values) {
			t.Fatalf("marker %d values = %+v, want %+v", i, got.values, fixture.Values)
		}
		for j := range got.values {
			if got.values[j] != fixture.Values[j] {
				t.Fatalf("marker %d values = %+v, want %+v", i, got.values, fixture.Values)
			}
		}
	}
}

func TestSanitizeInvokedBy_SharedFixtures(t *testing.T) {
	var fixtures []sanitizeFixture
	readSpecFixture(t, "sanitize-fixtures.json", &fixtures)

	for _, fixture := range fixtures {
		t.Run(fixture.Name, func(t *testing.T) {
			got, ok := sanitizeInvokedBy(fixture.Input)
			if ok != fixture.Valid {
				t.Fatalf("ok = %v, want %v", ok, fixture.Valid)
			}
			if got != fixture.Want {
				t.Fatalf("got = %q, want %q", got, fixture.Want)
			}
		})
	}
}

func TestClassifyParentName_SharedFixtures(t *testing.T) {
	var fixtures []parentFixture
	readSpecFixture(t, "parent-fixtures.json", &fixtures)

	for _, fixture := range fixtures {
		t.Run(fixture.Raw, func(t *testing.T) {
			if got := classifyParentName(fixture.Raw); got != fixture.Want {
				t.Fatalf("got = %q, want %q", got, fixture.Want)
			}
		})
	}
}

func TestHeadersAndUserAgentSuffix_SharedFixtures(t *testing.T) {
	var fixtures []headerFixture
	readSpecFixture(t, "header-fixtures.json", &fixtures)

	for _, fixture := range fixtures {
		t.Run(fixture.Name, func(t *testing.T) {
			signals := Signals{
				Interactive: fixture.Signals.Interactive,
				Parent:      fixture.Signals.Parent,
				Agent:       fixture.Signals.Agent,
				AgentSource: fixture.Signals.AgentSource,
				CI:          fixture.Signals.CI,
			}

			if got := headersFor(fixture.Prefix, signals); !equalStringMap(got, fixture.Headers) {
				t.Fatalf("headers = %+v, want %+v", got, fixture.Headers)
			}
			if got := userAgentSuffix(signals); got != fixture.UserAgentSuffix {
				t.Fatalf("User-Agent suffix = %q, want %q", got, fixture.UserAgentSuffix)
			}
		})
	}
}

func readSpecFixture(t *testing.T, name string, dst any) {
	t.Helper()

	body, err := os.ReadFile(filepath.Join("..", "spec", name))
	if err != nil {
		t.Fatalf("failed to read fixture %s: %v", name, err)
	}
	if err := json.Unmarshal(body, dst); err != nil {
		t.Fatalf("failed to decode fixture %s: %v", name, err)
	}
}

func matchKindName(kind matchKind) string {
	switch kind {
	case presence:
		return "presence"
	case exactValue:
		return "exactValue"
	default:
		return ""
	}
}

func equalStringMap(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for k, av := range a {
		if b[k] != av {
			return false
		}
	}
	return true
}
