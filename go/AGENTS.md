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
- `transport.go` — `ClientSignalsTransport`, `Signals.WrapTransport`, and
  header helpers.
- `cmd/` — small JSON inspection CLI.

## Constraints

- No new external dependencies beyond `golang.org/x/sys`.
- Do not shell out for parent-process lookup.
- `DetectOnce` must remain cached with `sync.OnceValue`.
- `ClientSignalsTransport` must not perform detection per request.
- Keep `knownMarkers` aligned with `../spec/markers.json`.

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
