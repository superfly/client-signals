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

The Plug can also invoke a caller-provided observer for requests whose matched
route template falls under configured API prefixes:

```elixir
plug ClientSignals.Plug,
  service: "my-api",
  tracked_route_prefixes: ["/api/v1"],
  request_observer: {MyApp.ClientSignals, :observe_api_request, []},
  route_template_provider: {MyApp.ClientSignals, :route_template, []}
```

The observer receives a map containing the bounded keys `service`,
`api_route`, `operator`, and `agent`. `api_route` combines the uppercase HTTP
method with the matched route template. Unmatched requests under a configured
prefix use `"METHOD unmatched"`; raw request paths are never forwarded.

The `operator` values are `ci`, `agent`, `interactive`,
`automated_unattributed`, and `uninstrumented`. The `agent` value is a known
finite agent name, `other`, or `none`. Parent is deliberately not used for
classification.

The package does not depend on or configure a metrics library. The observer,
route-template provider, metric name, service name, and tracked API prefixes
remain owned by each consuming service. For Phoenix, the route-template
provider can use `Phoenix.Router.route_info/4` with the application's router.

## Development

```sh
mix test
mix format --check-formatted
```
