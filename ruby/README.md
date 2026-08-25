# client_signals (Ruby)

Coarse, privacy-safe signals that help estimate whether traffic is driven by a
human or an AI agent, plus the bounded server-side classification of the
`Fly-Client-*` headers those signals produce.

No runtime dependencies, standard library only.

This is aggregate observability only. The signals are self-reported by the
client and must not be used for authentication, authorization, rate limiting,
enforcement, or any other per-request trust decision. The absence of an agent
marker is not evidence of a human.

## Install

```ruby
gem "client_signals", git: "https://github.com/superfly/client-signals", glob: "ruby/*.gemspec"
```

## Sending signals

Detect once per process and reuse the result. Detection reads the environment
and the parent process, so it does not belong on a per-request path.

```ruby
require "client_signals"

signals = ClientSignals.detect_once

signals.operator          # => "agent"
signals.agent             # => "claude-code"
signals.headers           # => {"Fly-Client-Interactive" => "false", ...}
signals.user_agent_suffix # => "(interactive=false; parent=node; agent=claude-code)"

signals.apply_headers(request_headers)
```

`headers` takes a `prefix:` for callers outside Fly.io, matching
`ApplyHeadersWithPrefix` in the Go package.

## Reading signals

`ClientSignals::Request` implements `spec/request-metrics.md`. Both values it
returns are safe to use as metric labels: a caller-supplied agent name never
reaches a label unless the marker table already knows it.

```ruby
require "client_signals/request"

ClientSignals::Request.classify_headers(request.headers)
# => {operator: "agent", agent: "claude-code"}

ClientSignals::Request.tracked_route("POST", "/v1/apps/:app/machines", "/v1/apps/x/machines", ["/v1"])
# => ["POST /v1/apps/:app/machines", true]
```

`classify_headers` reads the three headers off anything responding to `[]` with
a canonical header name, which covers a plain `Hash`, Rack's header hash and
`ActionDispatch::Http::Headers` alike. `classify(interactive, agent, ci)` takes
the values directly when they come from somewhere else.

## What is not here

No Rack middleware and no metric collector. Emitting
`fly_client_signals_requests_total` means opinionating on a Prometheus client,
and the one Ruby consumer today routes metrics through `prometheus_exporter`'s
own collector split. Classification is the reusable part; wiring stays with the
application.

`parent` is `other` on any platform without `/proc`, macOS included. Spawning a
subprocess to ask is forbidden by the repository invariants, and `other` is an
honest answer. The python package makes the same trade.

## Tests

```sh
cd ruby && rake test
```

The suite is driven by the shared fixtures in `../spec/`, the same files the go
and elixir packages are held to.
