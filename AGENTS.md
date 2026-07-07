# AGENTS.md

Context for coding agents working in this repo.

## What this is

`client-signals` computes coarse, privacy-safe signals used to estimate
whether a CLI process is human- or AI-agent-driven. This is a monorepo with
implementations for multiple programming languages and shared fixtures in
`spec/`.

Read `README.md` first. For the "why" behind the actual signal values and
detection logic — not just the "what" — read:

- `docs/signals.md` — reasoning behind each shared signal and its known
  reliability caveats.
- `docs/markers.md` — where the known agent-marker table came from, the
  confidence behind each entry, and the checklist for adding new ones.

## Layout

- `spec/` — shared markers and behavior fixtures for all languages.
- `docs/` — shared rationale and marker-review guidance.
- `go/` — Go package and language-specific agent instructions.
- `javascript/` — JavaScript package and language-specific agent instructions.
- `python/` — Python package and language-specific agent instructions.
- `elixir/` — Elixir package and language-specific agent instructions.

When working inside a language package, also read that package's
`AGENTS.md` and `README.md`.

## Invariants — do not casually relax these

- **Keep implementations dependency-light.** Do not add runtime
  dependencies unless the user explicitly asks and the tradeoff is
  justified.
- **Never spawn a subprocess for parent-process lookup.** Use native or
  filesystem process state where available, and fall back to `other`.
- **Signal detection must never run per HTTP request.** Each package must
  offer a cached detect-once path for long-lived clients.
- **Only finite, pre-approved values ever leave this package** (or a
  sanitized self-declaration, for `Agent`). Nothing here should vary in a
  way that's identifying per-user, per-machine, or per-repo.
- **Never read or forward secret-shaped environment variables**
  (anything token/key/credential-like), even for presence-checking.
- **Keep language implementations aligned with `spec/`.** Marker changes
  start in `spec/markers.json`, then get mirrored into each language's
  dependency-free runtime table and fixture-driven tests.

## Working in this repo

Run all package tests:

```sh
(cd go && go test ./...)
(cd javascript && npm test)
(cd python && python3 -m unittest)
(cd elixir && mix test)
```

CI (`.github/workflows/checks.yml`) runs Go tests on Linux, macOS, and
Windows, plus JavaScript, Python, Elixir, and Go lint jobs.

To cut a release: `scripts/bump_version.sh` (or `scripts/bump_version.sh
prerel` for a prerelease) from `main`, tagging and pushing a real GitHub
release via `.github/workflows/release.yml`. Don't run this without the
user's explicit go-ahead — it's a real, visible, hard-to-reverse action.
