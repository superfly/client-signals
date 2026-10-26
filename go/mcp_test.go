package clientsignals

import (
	"net/http"
	"strings"
	"testing"
)

type mcpClientFixture struct {
	Name       string            `json:"name"`
	Headers    map[string]string `json:"headers"`
	ClientName string            `json:"clientName"`
	Want       struct {
		Client   string `json:"client"`
		Source   string `json:"source"`
		Operator string `json:"operator"`
		Agent    string `json:"agent"`
	} `json:"want"`
}

func TestClassifyMCP_SharedFixtures(t *testing.T) {
	t.Parallel()

	var fixtures []mcpClientFixture
	readSpecFixture(t, "mcp-client-fixtures.json", &fixtures)

	for _, fixture := range fixtures {
		t.Run(fixture.Name, func(t *testing.T) {
			t.Parallel()

			header := make(http.Header, len(fixture.Headers))
			for name, value := range fixture.Headers {
				header.Set(name, value)
			}

			wantClient := MCPClient{Client: fixture.Want.Client, Source: fixture.Want.Source}
			if got := ClassifyMCPClient(header, fixture.ClientName); got != wantClient {
				t.Fatalf("ClassifyMCPClient() = %#v, want %#v", got, wantClient)
			}

			wantRequest := RequestClassification{
				Operator: fixture.Want.Operator,
				Agent:    fixture.Want.Agent,
			}
			if got := ClassifyMCPRequest(header, fixture.ClientName); got != wantRequest {
				t.Fatalf("ClassifyMCPRequest() = %#v, want %#v", got, wantRequest)
			}
		})
	}
}

// Requests without User-Agent, X-Anthropic-Client, or clientInfo must classify
// exactly as ClassifyRequestHeaders does.
func TestClassifyMCPRequest_MatchesRequestFixturesWithoutMCPInputs(t *testing.T) {
	t.Parallel()

	var fixtures []requestClassificationFixture
	readSpecFixture(t, "request-classification-fixtures.json", &fixtures)

	for _, fixture := range fixtures {
		t.Run(fixture.Name, func(t *testing.T) {
			t.Parallel()

			header := make(http.Header, len(fixture.Headers))
			for name, value := range fixture.Headers {
				header.Set(name, value)
			}
			header.Del("User-Agent")
			header.Del("X-Anthropic-Client")

			want := RequestClassification{
				Operator: fixture.Want.Operator,
				Agent:    fixture.Want.Agent,
			}
			if got := ClassifyMCPRequest(header, ""); got != want {
				t.Fatalf("ClassifyMCPRequest() = %#v, want %#v", got, want)
			}
			if got := ClassifyRequestHeaders(header); got != want {
				t.Fatalf("ClassifyRequestHeaders() = %#v, want %#v", got, want)
			}
		})
	}
}

// Every MCP client label must be a bounded identifier that survives agent
// normalization unchanged, so it reports identically via Fly-Client-Agent.
func TestMCPClientLabels_AreClosedUnderAgentNormalization(t *testing.T) {
	t.Parallel()

	for _, rule := range mcpClientRules {
		if got, ok := sanitizeInvokedBy(rule.client); !ok || got != rule.client {
			t.Fatalf("sanitizeInvokedBy(%q) = (%q, %t), want unchanged", rule.client, got, ok)
		}
		if strings.ToLower(rule.client) != rule.client {
			t.Fatalf("label %q is not lowercase", rule.client)
		}
		if got := normalizeRequestAgent(rule.client); got != rule.client {
			t.Fatalf("normalizeRequestAgent(%q) = %q, want unchanged", rule.client, got)
		}
		if rule.client == RequestAgentOther || rule.client == RequestAgentNone {
			t.Fatalf("label %q collides with a reserved agent value", rule.client)
		}
	}
	for _, marker := range knownMarkers {
		if got := normalizeRequestAgent(marker.agent); got != marker.agent {
			t.Fatalf("normalizeRequestAgent(%q) = %q, want unchanged", marker.agent, got)
		}
	}
}

// Caller-controlled inputs must never reach the output: the client is always a
// table label, "other", or "".
func TestClassifyMCPClient_NeverReturnsRawInput(t *testing.T) {
	t.Parallel()

	allowed := map[string]bool{"": true, RequestAgentOther: true}
	for _, rule := range mcpClientRules {
		allowed[rule.client] = true
	}
	sources := map[string]bool{
		MCPSourceVendorHeader: true,
		MCPSourceUserAgent:    true,
		MCPSourceClientInfo:   true,
		MCPSourceNone:         true,
	}

	inputs := []string{
		"",
		" ",
		"secret-token-abc123",
		"Bearer sk-live-1234",
		"my-private-client",
		"zed",
		"Cursor/1.0",
		"cursorish/1.0",
		"openai-mcp/1.0.0 (ChatGPT)",
		"claude-code (via mcp-remote 0.1.29)",
		" (via mcp-remote 0.1.29)",
		"Kilo",
		"\xff\xfe",
		strings.Repeat("A", 1024),
	}

	check := func(ua, vendor, name string) {
		t.Helper()

		header := http.Header{}
		header.Set("User-Agent", ua)
		header.Set("X-Anthropic-Client", vendor)

		got := ClassifyMCPClient(header, name)
		if !allowed[got.Client] || !sources[got.Source] {
			t.Fatalf("ClassifyMCPClient(%q, %q, %q) = %#v, want a bounded value", ua, vendor, name, got)
		}
		if (got.Client == "") != (got.Source == MCPSourceNone) {
			t.Fatalf("ClassifyMCPClient(%q, %q, %q) = %#v, want client and source to agree", ua, vendor, name, got)
		}

		request := ClassifyMCPRequest(header, name)
		if request.Operator == RequestOperatorMCP && request.Agent != got.Client {
			t.Fatalf("ClassifyMCPRequest() = %#v, want agent %q", request, got.Client)
		}
	}

	for _, ua := range inputs {
		for _, vendor := range inputs {
			for _, name := range inputs {
				check(ua, vendor, name)
			}
		}
	}

	var fixtures []mcpClientFixture
	readSpecFixture(t, "mcp-client-fixtures.json", &fixtures)
	for _, fixture := range fixtures {
		values := []string{fixture.ClientName}
		for _, value := range fixture.Headers {
			values = append(values, value)
		}
		for _, value := range values {
			for _, other := range inputs {
				check(value, other, other)
				check(other, value, other)
				check(other, other, value)
			}
		}
	}
}

func TestMCPClientNameFromMeta(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		meta map[string]any
		want string
	}{
		{name: "nil", meta: nil, want: ""},
		{name: "missing", meta: map[string]any{}, want: ""},
		{
			name: "client info name",
			meta: map[string]any{
				"io.modelcontextprotocol/clientInfo": map[string]any{
					"name":    "claude-code",
					"version": "2.1.309",
				},
			},
			want: "claude-code",
		},
		{
			name: "client info not an object",
			meta: map[string]any{"io.modelcontextprotocol/clientInfo": "claude-code"},
			want: "",
		},
		{
			name: "name not a string",
			meta: map[string]any{
				"io.modelcontextprotocol/clientInfo": map[string]any{"name": 42.0},
			},
			want: "",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			if got := MCPClientNameFromMeta(test.meta); got != test.want {
				t.Fatalf("MCPClientNameFromMeta() = %q, want %q", got, test.want)
			}
		})
	}
}
