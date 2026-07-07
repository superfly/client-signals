client-signals
==============

`client-signals` computes coarse, privacy-safe signals that help estimate
whether a CLI process is being driven by a human or an AI agent.

The project is a monorepo for the same behavior across multiple
programming languages. Every implementation follows the shared contract in
`spec/`: terminal attachment, a coarse parent-process bucket
(`node`/`python`/`shell`/`other`), a cooperative agent marker, and CI
detection.

These signals are meant to be combined into an *estimate with confidence*,
never treated as per-request certainty, and never used for gating,
blocking, rate-limiting, or auth decisions.

## Monorepo layout

- `spec/` — shared marker table and behavior fixtures.
- `go/` — Go implementation and package README.
- `javascript/` — JavaScript implementation and package README.
- `python/` — Python implementation and package README.
- `elixir/` — Elixir implementation and package README.
- `docs/` — shared signal rationale and marker-review guidance.

The language packages intentionally expose the same library-only surface:
detect signals once, build/apply `{prefix}-Client-*` headers, and build the
client-signals User-Agent suffix. See each package README for language
specific installation, API names, and examples.

## Shared contract

All implementations must preserve these invariants:

- Only finite, pre-approved values leave the package, except sanitized
  self-declarations from `FLY_INVOKED_BY` or `AGENT`.
- Secret-shaped environment variables are never read or forwarded, even
  for presence checks.
- Parent process names are collapsed to `node`, `python`, `shell`, or
  `other`; raw process names are never emitted.
- Detection is computed once for long-lived clients and must not run per
  HTTP request.
- Header prefix defaults to `Fly`, producing names like
  `Fly-Client-Interactive` and `Fly-Client-Parent`.

## Development

Run all package tests:

```sh
(cd go && go test ./...)
(cd javascript && npm test)
(cd python && python3 -m unittest)
(cd elixir && mix test)
```

Go platform build checks:

```sh
(cd go && GOOS=linux GOARCH=amd64 go build ./...)
(cd go && GOOS=darwin GOARCH=arm64 go build ./...)
(cd go && GOOS=windows GOARCH=amd64 go build ./...)
```

See [docs/signals.md](docs/signals.md) for signal rationale and
[docs/markers.md](docs/markers.md) for marker-review guidance.

## Releases

The existing tag workflow creates a GitHub release. npm, PyPI, and Hex
publishing are not automated yet.
