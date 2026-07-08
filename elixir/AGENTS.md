# AGENTS.md

Elixir-specific notes for agents working in `elixir/`.

## Package

This directory is the Hex package `:client_signals`.

Runtime target: Elixir 1.15 or newer.

Key files:

- `lib/client_signals.ex` — runtime implementation and exported API.
- `lib/client_signals/plug.ex` — `ClientSignals.Plug`, the consumer side:
  reads `Fly-Client-*` request headers and attaches them as OTel span
  attributes. Only defined when both optional deps are loaded (see below).
- `test/client_signals_test.exs` — ExUnit suite, including shared fixture
  checks.
- `test/client_signals/plug_test.exs` — `ClientSignals.Plug` tests.
- `mix.exs` — package metadata.

## Constraints

- The core signal-detection API (`lib/client_signals.ex`) has no runtime
  dependencies.
- `:plug` and `:opentelemetry_api` are declared as `optional: true` deps
  solely so `ClientSignals.Plug` can exist. This is a deliberate, narrow
  exception to "no runtime dependencies" — justified because
  `ClientSignals.Plug` is a server-side consumer of the headers this
  package produces, only used by services that already depend on Plug and
  OpenTelemetry (e.g. a Phoenix app), and the whole module is skipped at
  compile time (`Code.ensure_loaded?/1` guard) for anyone who doesn't have
  both. Do not add further optional or hard dependencies without asking.
- Do not shell out for parent-process lookup.
- `detect_once/0` must cache the first detected value.
- Keep `known_markers/0` aligned with `../spec/markers.json`.

## Commands

```sh
mix test
mix format --check-formatted
```
