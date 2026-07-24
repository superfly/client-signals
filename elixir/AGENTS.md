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
- `lib/client_signals/request_metrics.ex` — emits the canonical bounded
  request telemetry event.
- `lib/client_signals/prom_ex_plugin.ex` — optional PromEx definition for the
  canonical request counter.
- `test/client_signals_test.exs` — ExUnit suite, including shared fixture
  checks.
- `test/client_signals/plug_test.exs` — `ClientSignals.Plug` tests.
- `mix.exs` — package metadata.

## Constraints

- The core signal-detection API (`lib/client_signals.ex`) has no runtime
  dependencies.
- `:plug`, `:opentelemetry_api`, `:telemetry`, and `:prom_ex` are declared as
  `optional: true` deps for the server-side integrations. This is a deliberate
  exception to "no runtime dependencies": these integrations are used by
  services that already depend on the relevant libraries, and guarded modules
  are skipped at compile time when their dependencies are absent. Do not add
  further optional or hard dependencies without asking.
- Do not shell out for parent-process lookup.
- `detect_once/0` must cache the first detected value.
- Keep `known_markers/0` aligned with `../spec/markers.json`.

## Commands

```sh
mix test
mix format --check-formatted
```
