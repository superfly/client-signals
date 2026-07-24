package clientsignals

import (
	"net/http"
	"testing"
)

func TestClassifyRequestHeaders(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		header http.Header
		want   RequestClassification
	}{
		{
			name:   "missing instrumentation sentinel",
			header: http.Header{"Fly-Client-Agent": {"codex"}},
			want: RequestClassification{
				Operator: RequestOperatorUninstrumented,
				Agent:    RequestAgentNone,
			},
		},
		{
			name: "invalid instrumentation sentinel",
			header: http.Header{
				"Fly-Client-Interactive": {"maybe"},
				"Fly-Client-Agent":       {"codex"},
			},
			want: RequestClassification{
				Operator: RequestOperatorUninstrumented,
				Agent:    RequestAgentNone,
			},
		},
		{
			name: "CI takes precedence and preserves agent",
			header: http.Header{
				"Fly-Client-Interactive": {"false"},
				"Fly-Client-Agent":       {"codex"},
				"Fly-Client-Ci":          {"true"},
			},
			want: RequestClassification{
				Operator: RequestOperatorCI,
				Agent:    "codex",
			},
		},
		{
			name: "known agent",
			header: http.Header{
				"Fly-Client-Interactive": {"true"},
				"Fly-Client-Agent":       {"claude-code"},
			},
			want: RequestClassification{
				Operator: RequestOperatorAgent,
				Agent:    "claude-code",
			},
		},
		{
			name: "unknown sanitized declaration is bounded",
			header: http.Header{
				"Fly-Client-Interactive": {"false"},
				"Fly-Client-Agent":       {"my-agent"},
			},
			want: RequestClassification{
				Operator: RequestOperatorAgent,
				Agent:    RequestAgentOther,
			},
		},
		{
			name: "invalid agent is ignored",
			header: http.Header{
				"Fly-Client-Interactive": {"false"},
				"Fly-Client-Agent":       {"bad agent value"},
			},
			want: RequestClassification{
				Operator: RequestOperatorAutomatedUnattributed,
				Agent:    RequestAgentNone,
			},
		},
		{
			name: "interactive",
			header: http.Header{
				"Fly-Client-Interactive": {"true"},
			},
			want: RequestClassification{
				Operator: RequestOperatorInteractive,
				Agent:    RequestAgentNone,
			},
		},
		{
			name: "automated unattributed",
			header: http.Header{
				"Fly-Client-Interactive": {"false"},
			},
			want: RequestClassification{
				Operator: RequestOperatorAutomatedUnattributed,
				Agent:    RequestAgentNone,
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := ClassifyRequestHeaders(tt.header); got != tt.want {
				t.Fatalf("ClassifyRequestHeaders() = %#v, want %#v", got, tt.want)
			}
		})
	}
}

func TestTrackedAPIRoute(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name          string
		method        string
		routeTemplate string
		requestPath   string
		prefixes      []string
		want          string
		wantTracked   bool
	}{
		{
			name:          "matched route",
			method:        "post",
			routeTemplate: "/v1/apps/{app}/machines/{id}",
			requestPath:   "/v1/apps/my-app/machines/123",
			prefixes:      []string{"/v1"},
			want:          "POST /v1/apps/{app}/machines/{id}",
			wantTracked:   true,
		},
		{
			name:          "prefix boundary",
			method:        "GET",
			routeTemplate: "/v10/apps",
			requestPath:   "/v10/apps",
			prefixes:      []string{"/v1"},
			wantTracked:   false,
		},
		{
			name:        "unmatched API path",
			method:      "get",
			requestPath: "/api/v1/not-a-route/123",
			prefixes:    []string{"/api/v1"},
			want:        "GET unmatched",
			wantTracked: true,
		},
		{
			name:        "unmatched non-API path",
			method:      "GET",
			requestPath: "/dashboard",
			prefixes:    []string{"/api/v1"},
			wantTracked: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, tracked := TrackedAPIRoute(
				tt.method,
				tt.routeTemplate,
				tt.requestPath,
				tt.prefixes,
			)
			if got != tt.want || tracked != tt.wantTracked {
				t.Fatalf(
					"TrackedAPIRoute() = (%q, %t), want (%q, %t)",
					got,
					tracked,
					tt.want,
					tt.wantTracked,
				)
			}
		})
	}
}
