# client-signals for Go

Go implementation of the shared `client-signals` contract.

## Installation

```sh
go get github.com/superfly/client-signals/go
```

The package name is `clientsignals`:

```go
import clientsignals "github.com/superfly/client-signals/go"
```

## Usage

```go
sig := clientsignals.DetectOnce()

header := http.Header{}
sig.ApplyHeaders(header)
```

To wrap an `http.Client` transport:

```go
httpClient := &http.Client{
    Transport: sig.WrapTransport(http.DefaultTransport),
}
```

Use a custom header prefix with `ApplyHeadersWithPrefix` or
`WrapTransportWithPrefix`:

```go
sig.ApplyHeadersWithPrefix(header, "Acme")
```

## API

- `Detect() Signals` computes fresh signals.
- `DetectOnce() Signals` computes and caches process-wide signals.
- `Signals.Operator()` returns `ci`, `agent`, `interactive`, or `unknown`;
  precedence is in that order.
- `Signals.ApplyHeaders(http.Header)` applies `Fly-Client-*` headers.
- `Signals.ApplyHeadersWithPrefix(http.Header, string)` applies custom
  prefix headers.
- `Signals.WrapTransport(http.RoundTripper)` wraps a transport and appends
  the User-Agent suffix.
- `Signals.WrapTransportWithPrefix(http.RoundTripper, string)` wraps with a
  custom header prefix.
- `ClassifyRequestHeaders(http.Header)` returns bounded `operator` and `agent`
  values for server-side metrics. `Fly-Client-Interactive` is the
  instrumentation sentinel; Parent is not used.
- `TrackedRoute(method, routeTemplate, requestPath, prefixes)` selects
  configured route prefixes and returns a bounded `"METHOD /route/{template}"`
  label. Raw paths are never returned for unmatched requests.
- `NewRequestCounter(service, trackedRoutePrefixes)` constructs the canonical
  `fly_client_signals_requests_total` Prometheus collector. Register it with
  the service's Prometheus registry and call `Observe(request, routeTemplate)`
  after routing.
- `ClassifyMCPClient(http.Header, clientName)` infers a bounded MCP client
  label and its source (`vendor_header`, `user_agent`, `client_info`, or
  `none`) from `X-Anthropic-Client`, `User-Agent`, and `clientInfo.name`.
- `ClassifyMCPRequest(http.Header, clientName)` is `ClassifyRequestHeaders`
  for declared MCP routes: a valid `Fly-Client-Interactive` self-report wins;
  otherwise an identified MCP client yields operator `mcp`.
- `MCPClientNameFromMeta(map[string]any)` reads
  `io.modelcontextprotocol/clientInfo.name` from a decoded `params._meta`
  (go-sdk's `mcp.Meta`, or mcp-go's `Meta.AdditionalFields`).
- `RequestCounter.ObserveMCP(request, routeTemplate, clientName)` is `Observe`
  using `ClassifyMCPRequest`; call it only for the service's MCP routes.

## Server-side request metrics

`ClassifyRequestHeaders` uses the following operator precedence:
`ci > agent > interactive > automated_unattributed`. A missing or invalid
`Fly-Client-Interactive` header produces `uninstrumented`.

Known agents retain their finite marker-table or MCP client-table name. Valid sanitized
self-declarations not in that table become `other`; missing or invalid agent
values become `none`. This makes both fields suitable for metric labels without
allowing caller-controlled cardinality.

The request counter owns the canonical metric name, help text, label order,
route filtering, and request classification. The consuming service remains
responsible for registering the collector and providing its bounded service
name, tracked route prefixes, and router-owned route template.

## MCP client identity

MCP clients do not send `Fly-Client-*` headers, so on routes the service
declares as MCP routes it can opt in to inferring the client instead. Never
apply this to ordinary REST routes: some matched User-Agents (such as
`Claude-User`) are also sent by non-MCP fetches.

```go
var clientName string // initialize params.clientInfo.name, or:

// modelcontextprotocol/go-sdk, where mcp.Meta is a map[string]any:
clientName = clientsignals.MCPClientNameFromMeta(params.Meta)

// mark3labs/mcp-go, where toolReq is the mcp.CallToolRequest and its
// Params.Meta is a *mcp.Meta that may be nil and keeps the _meta keys it does
// not model in AdditionalFields:
if m := toolReq.Params.Meta; m != nil {
	clientName = clientsignals.MCPClientNameFromMeta(m.AdditionalFields)
}

// httpReq is the *http.Request for the MCP route: the handler's request in
// go-sdk, or one stashed in ctx via server.WithHTTPContextFunc in mcp-go.
counter.ObserveMCP(httpReq, "/mcp", clientName)
```

Precedence is vendor header, then User-Agent, then `clientInfo.name`, with
weak (pooled) rules last. A `clientInfo.name` that matches no rule becomes
`other`; an unrecognized User-Agent or vendor header alone produces no client,
so scanners and curl stay `uninstrumented`. Labels come from the finite table
in `mcp_clients.go`, mirrored from `../spec/mcp-clients.json`; raw User-Agent
and `clientInfo` values are never returned. The inferred client is for
reporting only, never for gating. See `../spec/request-metrics.md` and
`../docs/mcp-clients.md`.

The known-agent vocabulary used for `Fly-Client-Agent` is the marker table
plus the MCP client labels, so `Fly-Client-Agent: zed` reports `zed`.

The Go module lives under `go/`; consumers of the old root module path must
update imports to `github.com/superfly/client-signals/go`.

## Development

```sh
go test ./...
go build ./...
GOOS=linux GOARCH=amd64 go build ./...
GOOS=darwin GOARCH=arm64 go build ./...
GOOS=windows GOARCH=amd64 go build ./...
```
