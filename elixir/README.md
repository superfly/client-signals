# client-signals for Elixir

Elixir implementation of the shared `client-signals` contract.

## Installation

Add `:client_signals` to your Mix dependencies when the package is
published:

```elixir
def deps do
  [
    {:client_signals, "~> 0.4"}
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

The Plug emits the canonical `[:client_signals, :request]` telemetry event for
requests whose matched route template falls under configured prefixes:

```elixir
plug ClientSignals.Plug,
  service: "my-api",
  tracked_route_prefixes: ["/api/v1"],
  route_template_provider: {MyApp.ClientSignals, :route_template, []}
```

Add `ClientSignals.PromExPlugin` to the application's PromEx plugins to export
`fly_client_signals_requests_total`:

```elixir
def plugins do
  [
    ClientSignals.PromExPlugin
  ]
end
```

The telemetry event contains the bounded metadata keys `service`,
`route`, `operator`, and `agent`. `route` combines the uppercase HTTP
method with the matched route template. Unmatched requests under a configured
prefix use `"METHOD unmatched"`; raw request paths are never forwarded.

The `operator` values are `ci`, `agent`, `interactive`,
`automated_unattributed`, `uninstrumented`, and (on MCP routes only) `mcp`.
The `agent` value is a known finite agent name or MCP client label, `other`,
or `none`. Parent is deliberately not used for classification.

### MCP routes

MCP clients do not send `Fly-Client-*` headers, but they do identify
themselves through `clientInfo.name`, `User-Agent`, and `X-Anthropic-Client`.
List the routes that serve MCP in `:mcp_route_prefixes` to infer a bounded
client label for them:

```elixir
plug ClientSignals.Plug,
  service: "my-mcp",
  tracked_route_prefixes: ["/mcp"],
  mcp_route_prefixes: ["/mcp"],
  route_template_provider: {MyApp.ClientSignals, :route_template, []}
```

On those routes a valid `Fly-Client-Interactive` header still wins for the
metric labels. Otherwise an identified client is reported as
`operator: "mcp"` with the client label (or `other`) as the agent. Independent
of the metric, whenever a client is identified on an MCP route the Plug sets
the `fly.client.mcp_client` and `fly.client.mcp_source` span attributes, even
when the request also self-reports and even when the route is not in
`:tracked_route_prefixes`. `clientInfo.name` is read from `conn.body_params`
when the response is sent, so it only needs a JSON `Plug.Parsers` somewhere in
the pipeline; an unfetched body is ignored. Do not list ordinary REST routes:
`Claude-User` is also the User-Agent of Claude Code's web fetches.

On protocol versions up to 2025-11-25 `clientInfo` is sent only on
`initialize`, so clients without a distinctive User-Agent (OpenCode, Gemini
CLI, Cline, and others) are labelled on that call only. Compare such clients
by `initialize` volume. See the stateless caveat in
[`spec/request-metrics.md`](../spec/request-metrics.md).

Without a Plug, use `ClientSignals.MCP` directly:

- `ClientSignals.MCP.classify_client/3` takes the User-Agent,
  `X-Anthropic-Client`, and `clientInfo.name` values and returns
  `%{client: label, source: source}`.
- `ClientSignals.MCP.classify_request/6` adds the three `Fly-Client-*` header
  values and returns `%{operator: operator, agent: agent}`.
- `ClientSignals.MCP.client_name/1` extracts `clientInfo.name` from a decoded
  JSON-RPC request or its params.

These values are inferred from caller-controlled input. Use them for
estimates only, never for gating. The rules live in
[`spec/mcp-clients.json`](../spec/mcp-clients.json); see
[`docs/mcp-clients.md`](../docs/mcp-clients.md) for their provenance.

The package owns the canonical telemetry event and PromEx metric definition.
The route-template provider, service name, tracked route prefixes, PromEx
supervision, and collector registration remain owned by each consuming
service. A custom `request_observer` MFA remains supported. For Phoenix, the
route-template provider can use `Phoenix.Router.route_info/4` with the
application's router.

## Development

```sh
mix test
mix format --check-formatted
mix compile --warnings-as-errors
```
