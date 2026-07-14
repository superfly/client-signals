# client-signals for Elixir

Elixir implementation of the shared `client-signals` contract.

## Installation

Add `:client_signals` to your Mix dependencies when the package is
published:

```elixir
def deps do
  [
    {:client_signals, "~> 0.0.0"}
  ]
end
```

Requires Elixir 1.15 or newer.

## Usage

```elixir
signals = ClientSignals.detect_once()
headers = %{}

headers = ClientSignals.apply_headers(headers, signals)
Map.put(headers, "User-Agent", "my-cli/1.0 " <> ClientSignals.user_agent_suffix(signals))
```

Use a custom header prefix:

```elixir
ClientSignals.apply_headers(headers, signals, "Acme")
```

## API

- `ClientSignals.detect/0` computes fresh signals.
- `ClientSignals.detect_once/0` computes and caches process-wide signals.
- `ClientSignals.headers_for/2` returns a header map.
- `ClientSignals.apply_headers/3` merges signal headers into a map.
- `ClientSignals.user_agent_suffix/1` returns the client-signals
  User-Agent token.
- `ClientSignals.operator/1` returns `ci`, `agent`, `interactive`, or
  `unknown`; precedence is in that order.
- `ClientSignals.sanitize_invoked_by/1` and
  `ClientSignals.classify_parent_name/1` are exposed for tests and
  advanced consumers that need the shared contract helpers.

## Server-side: recording signals on request spans

If your application already depends on `:plug` and `:opentelemetry_api`
(e.g. a Phoenix app), `ClientSignals.Plug` reads the `Fly-Client-*`
headers off incoming requests and attaches them as `fly.client.*`
attributes on the current OTel span:

```elixir
# in your endpoint or router
plug ClientSignals.Plug
```

This module is only defined when both dependencies are present, so it
has no effect on consumers that only use the header-generation API above.

## Development

```sh
mix test
mix format --check-formatted
```
