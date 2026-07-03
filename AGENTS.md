# AGENTS.md

Context for coding agents working in this repo.

## What this is

`clientsignals` computes coarse, privacy-safe signals used to estimate
whether a CLI process is human- or AI-agent-driven, and provides an
`http.RoundTripper` wrapper (`Signals.WrapTransport`) that attaches them to
outbound requests. It's a single-purpose leaf library with no dependents
of its own.

Read `README.md` first. For the "why" behind the actual signal values and
detection logic — not just the "what" — read:

- `docs/signals.md` — reasoning behind each `Signals` field and its known
  reliability caveats (parent-process detection especially is noisier than
  it looks).
- `docs/markers.md` — where the known agent-marker table came from, the
  confidence behind each entry, and the checklist for adding new ones.

## Layout

- `signals.go` — the `Signals` struct, `Detect()`/`DetectOnce()`.
- `interactive.go` — terminal-attachment check.
- `parent.go` + `parent_{linux,darwin,windows,other}.go` — parent-process
  bucket, one implementation per OS via build tags.
- `agent.go` + `markers.go` — cooperative agent-marker detection.
- `ci.go` — CI detection.
- `transport.go` — `ClientSignalsTransport`, `Signals.WrapTransport`, and
  `Signals.ApplyHeaders`/`ApplyHeadersWithPrefix` for non-`http.RoundTripper`
  consumers (e.g. WebSocket handshakes) that need the same headers without
  a transport to wrap.
- `cmd/` — a small CLI (`go run ./cmd`) that prints currently-detected
  signals as JSON; useful for manually checking behavior under different
  invocation contexts (piped, under an agent harness, etc.).

## Invariants — do not casually relax these

- **No new external dependencies beyond `golang.org/x/sys`.** Keeping this
  a near-zero-dependency leaf is deliberate.
- **Never spawn a subprocess for parent-process lookup.** Linux reads
  `/proc`, Darwin uses a direct `sysctl` via `golang.org/x/sys/unix`,
  Windows walks a Toolhelp32 snapshot via `golang.org/x/sys/windows` — no
  shelling out to `ps`/`tasklist`.
- **Signal detection must never run per HTTP request.** `DetectOnce`
  caches via `sync.OnceValue`; `ClientSignalsTransport` computes once at
  construction and reuses the result for every request it forwards.
- **Only finite, pre-approved values ever leave this package** (or a
  sanitized self-declaration, for `Agent`). Nothing here should vary in a
  way that's identifying per-user, per-machine, or per-repo — see the
  "litmus test" in `docs/markers.md`.
- **Never read or forward secret-shaped environment variables**
  (anything token/key/credential-like), even for presence-checking.

## Working in this repo

Build/test/lint:

```sh
go build ./...
go test ./...
golangci-lint run ./...
gofmt -l .
```

`parent_{linux,darwin,windows}.go` are build-tag-gated — only one compiles
natively on your machine. Cross-compile the others to catch build breaks
before CI does:

```sh
GOOS=linux GOARCH=amd64 go build ./...
GOOS=darwin GOARCH=arm64 go build ./...
GOOS=windows GOARCH=amd64 go build ./...
```

CI (`.github/workflows/checks.yml`) runs `go test ./...` on Linux, macOS,
and Windows plus `golangci-lint`, so a change that only compiles on one
platform will fail there even if it passes locally.

To cut a release: `scripts/bump_version.sh` (or `scripts/bump_version.sh
prerel` for a prerelease) from `main`, tagging and pushing a real GitHub
release via `.github/workflows/release.yml`. Don't run this without the
user's explicit go-ahead — it's a real, visible, hard-to-reverse action.
