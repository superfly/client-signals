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

## Server-side request metrics

`ClassifyRequestHeaders` uses the following operator precedence:
`ci > agent > interactive > automated_unattributed`. A missing or invalid
`Fly-Client-Interactive` header produces `uninstrumented`.

Known agents retain their finite marker-table name. Valid sanitized
self-declarations not in that table become `other`; missing or invalid agent
values become `none`. This makes both fields suitable for metric labels without
allowing caller-controlled cardinality.

The request counter owns the canonical metric name, help text, label order,
route filtering, and request classification. The consuming service remains
responsible for registering the collector and providing its bounded service
name, tracked route prefixes, and router-owned route template.

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
