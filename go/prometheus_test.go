package clientsignals

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestRequestCounterObserve(t *testing.T) {
	t.Parallel()

	counter := NewRequestCounter("flaps", []string{"/v1"})
	registry := prometheus.NewPedanticRegistry()
	registry.MustRegister(counter)

	req := httptest.NewRequest(http.MethodPost, "/v1/apps/example/machines", nil)
	req.Header.Set("Fly-Client-Interactive", "false")
	req.Header.Set("Fly-Client-Agent", "codex")

	if !counter.Observe(req, "/v1/apps/{app_name}/machines") {
		t.Fatal("Observe() = false, want true")
	}

	const want = `
# HELP fly_client_signals_requests_total Requests classified by coarse client signals
# TYPE fly_client_signals_requests_total counter
fly_client_signals_requests_total{agent="codex",operator="agent",route="POST /v1/apps/{app_name}/machines",service="flaps"} 1
`
	if err := testutil.GatherAndCompare(registry, strings.NewReader(want), RequestMetricName); err != nil {
		t.Fatal(err)
	}
}

func TestRequestCounterDoesNotObserveUntrackedRoute(t *testing.T) {
	t.Parallel()

	counter := NewRequestCounter("flaps", []string{"/v1"})
	req := httptest.NewRequest(http.MethodGet, "/health", nil)

	if counter.Observe(req, "/health") {
		t.Fatal("Observe() = true, want false")
	}
	if got := testutil.CollectAndCount(counter); got != 0 {
		t.Fatalf("metric count = %d, want 0", got)
	}
}

func TestRequestCounterObserveMCP(t *testing.T) {
	t.Parallel()

	counter := NewRequestCounter("flyio-mcp", []string{"/mcp"})
	registry := prometheus.NewPedanticRegistry()
	registry.MustRegister(counter)

	inferred := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	inferred.Header.Set("User-Agent", "claude-code/2.1.309 (cli)")

	instrumented := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	instrumented.Header.Set("User-Agent", "claude-code/2.1.309 (cli)")
	instrumented.Header.Set("Fly-Client-Interactive", "true")

	unknown := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	unknown.Header.Set("User-Agent", "curl/8.7.1")

	for _, observed := range []struct {
		req        *http.Request
		clientName string
	}{
		{req: inferred, clientName: ""},
		{req: instrumented, clientName: "claude-code"},
		{req: unknown, clientName: ""},
		{req: unknown, clientName: "my-private-client"},
	} {
		if !counter.ObserveMCP(observed.req, "/mcp", observed.clientName) {
			t.Fatal("ObserveMCP() = false, want true")
		}
	}

	const want = `
# HELP fly_client_signals_requests_total Requests classified by coarse client signals
# TYPE fly_client_signals_requests_total counter
fly_client_signals_requests_total{agent="claude-code",operator="mcp",route="POST /mcp",service="flyio-mcp"} 1
fly_client_signals_requests_total{agent="none",operator="interactive",route="POST /mcp",service="flyio-mcp"} 1
fly_client_signals_requests_total{agent="none",operator="uninstrumented",route="POST /mcp",service="flyio-mcp"} 1
fly_client_signals_requests_total{agent="other",operator="mcp",route="POST /mcp",service="flyio-mcp"} 1
`
	if err := testutil.GatherAndCompare(registry, strings.NewReader(want), RequestMetricName); err != nil {
		t.Fatal(err)
	}
}

func TestRequestCounterObserveMCPDoesNotObserveUntrackedRoute(t *testing.T) {
	t.Parallel()

	counter := NewRequestCounter("flyio-mcp", []string{"/mcp"})
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("User-Agent", "claude-code/2.1.309 (cli)")

	if counter.ObserveMCP(req, "/health", "claude-code") {
		t.Fatal("ObserveMCP() = true, want false")
	}
	if got := testutil.CollectAndCount(counter); got != 0 {
		t.Fatalf("metric count = %d, want 0", got)
	}
}
