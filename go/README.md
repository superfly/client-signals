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
- `Signals.ApplyHeaders(http.Header)` applies `Fly-Client-*` headers.
- `Signals.ApplyHeadersWithPrefix(http.Header, string)` applies custom
  prefix headers.
- `Signals.WrapTransport(http.RoundTripper)` wraps a transport and appends
  the User-Agent suffix.
- `Signals.WrapTransportWithPrefix(http.RoundTripper, string)` wraps with a
  custom header prefix.

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
