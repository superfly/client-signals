# AGENTS.md

Go-specific notes for agents working in `go/`.

## Package

This directory is the Go module `github.com/superfly/client-signals/go`.
The package name is `clientsignals`.

Key files:

- `signals.go` — `Signals`, `Detect()`, and `DetectOnce()`.
- `interactive.go` — terminal-attachment check.
- `parent.go` plus `parent_{linux,darwin,windows,other}.go` —
  parent-process lookup and finite bucket classification.
- `agent.go` and `markers.go` — cooperative agent-marker detection.
- `ci.go` — CI detection.
- `request.go` and `prometheus.go` — server-side request classification and
  the canonical request counter.
- `mcp.go` and `mcp_clients.go` — opt-in MCP client inference for declared MCP
  routes (`ClassifyMCPClient`, `ClassifyMCPRequest`, `ObserveMCP`).
- `transport.go` — `ClientSignalsTransport`, `Signals.WrapTransport`, and
  header helpers.
- `cmd/` — small JSON inspection CLI.

## Constraints

- Runtime dependencies are limited to `golang.org/x/sys` for signal detection
  and `github.com/prometheus/client_golang` for the canonical server request
  collector. Do not add further dependencies without asking.
- Do not shell out for parent-process lookup.
- `DetectOnce` must remain cached with `sync.OnceValue`.
- `ClientSignalsTransport` must not perform detection per request.
- Keep `knownMarkers` aligned with `../spec/markers.json`.
- Keep `mcpClientRules` aligned with `../spec/mcp-clients.json`, in the same
  order. MCP rule changes start in the spec, not here.
- MCP normalization is byte-oriented: lowercase ASCII only (never
  `strings.ToLower`), and never return or label raw User-Agent or
  `clientInfo` values.

## Commands

```sh
go build ./...
go test ./...
golangci-lint run ./...
gofmt -l .
```

Cross-compile OS-specific parent lookup files:

```sh
GOOS=linux GOARCH=amd64 go build ./...
GOOS=darwin GOARCH=arm64 go build ./...
GOOS=windows GOARCH=amd64 go build ./...
```
