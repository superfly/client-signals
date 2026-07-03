client-signals
==============

Computes coarse, privacy-safe signals that help estimate whether a CLI
process is being driven by a human or an AI agent: terminal attachment, a
coarse parent-process bucket (`node`/`python`/`shell`/`other`), a
cooperative agent marker (self-declared via `FLY_INVOKED_BY`, or passively
detected from known agent-harness environment variables), and CI detection.

These are meant to be combined into an *estimate with confidence*, never
treated as per-request certainty, and never used for gating, blocking,
rate-limiting, or auth decisions.

Extracted from [fly-go](https://github.com/superfly/fly-go), which is
currently its only consumer.

## Usage

```go
sig := clientsignals.DetectOnce()

httpClient := &http.Client{
    Transport: sig.WrapTransport(http.DefaultTransport),
}
```

`ClientSignalsTransport` (returned by `Signals.WrapTransport`) attaches
`Fly-Client-*` headers and a `(interactive=...; parent=...; agent=...)`
User-Agent suffix to every request it forwards. Detection happens once,
at the point you call `Detect()`/`DetectOnce()` — never per request.

## Inspecting signals

```sh
go run ./cmd
```

prints the currently-detected signals as JSON.

## Privacy

- Only approved, finite values are ever emitted (see `Signals` field docs).
- Agent detection is presence/exact-value based; secret-shaped environment
  variables are never read or forwarded.
- `FLY_INVOKED_BY` (and the cross-tool `AGENT` convention) are sanitized and
  length-capped before being emitted anywhere.

## Cutting a Release

If you have write access to this repo, you can ship a release with:

`scripts/bump_version.sh`

Or a prerelease with:

`scripts/bump_version.sh prerel`

The release and notes will be created automatically via Github Actions. Follow along in: https://github.com/superfly/client-signals/actions/workflows/release.yml
