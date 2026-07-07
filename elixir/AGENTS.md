# AGENTS.md

Elixir-specific notes for agents working in `elixir/`.

## Package

This directory is the Hex package `:client_signals`.

Runtime target: Elixir 1.15 or newer.

Key files:

- `lib/client_signals.ex` — runtime implementation and exported API.
- `test/client_signals_test.exs` — ExUnit suite, including shared fixture
  checks.
- `mix.exs` — package metadata.

## Constraints

- No runtime dependencies.
- Do not shell out for parent-process lookup.
- `detect_once/0` must cache the first detected value.
- Keep `known_markers/0` aligned with `../spec/markers.json`.

## Commands

```sh
mix test
mix format --check-formatted
```
