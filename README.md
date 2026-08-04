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

The Go and Elixir packages also expose server-side helpers that classify
incoming headers into bounded metric-label values. The Go package provides the
canonical Prometheus request collector, while the Elixir package provides the
canonical telemetry event and PromEx plugin. Consuming services remain
responsible for metric registration, service names, route templates, and
tracked route prefixes. See
[spec/request-metrics.md](spec/request-metrics.md) for the shared
classification, labeling, and cardinality contract.

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

Pushing a final `vX.Y.Z` tag creates a GitHub release and publishes the same
version to PyPI, npm, and Hex. Each package manifest keeps a `0.0.0`
placeholder in the repository; its publishing workflow stamps the version
from the tag before testing, building, and publishing.

- PyPI uses trusted publishing via GitHub OIDC.
- npm uses trusted publishing via GitHub OIDC. Configure `@fly/client-signals`
  with organization `superfly`, repository `client-signals`, workflow
  `publish-javascript.yml`, and permission to run `npm publish`. No npm token
  or Actions secret is used.
- Hex uses the `HEX_API_KEY` Actions secret. Generate a dedicated CI key with
  `mix hex.user key generate --key-name github-actions-publish --permission api:write`.

Only final release tags are published. Prerelease tags such as
`v0.5.0-pre-1` still create GitHub prereleases but are intentionally excluded
from all three package registries.

npm requires a package to exist before its trusted publisher can be
configured. An `@fly` npm maintainer must bootstrap `@fly/client-signals`
once, then configure the trusted publisher above before the next release tag.
