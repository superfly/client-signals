# Server-side request metric contract

This document defines the shared, language-neutral contract for classifying
incoming `Fly-Client-*` headers and selecting bounded API-route labels.
Implementations may expose different APIs, but must produce the results in
`request-classification-fixtures.json` and `api-route-fixtures.json`.

This contract is for aggregate observability only. Client signals are
self-reported and must not be used for authentication, authorization,
rate-limiting, enforcement, or other per-request trust decisions.

## Canonical counter

Consuming API services should expose one Prometheus counter:

```text
fly_api_client_requests_total{
  service,
  api_route,
  operator,
  agent
}
```

The library does not register this counter. Metric registration, the bounded
`service` value, the route-template provider, and the tracked API prefixes
belong to each consuming service.

`parent` and `agent_source` are deliberately not metric labels. Parent-process
lookup is not reliable enough for request classification, and agent source is
not needed for aggregate traffic reporting.

## Request classification

`Fly-Client-Interactive` is the instrumentation sentinel. If it is missing or
is not a supported boolean value, the result is:

```json
{"operator": "uninstrumented", "agent": "none"}
```

Supported case-insensitive boolean values are:

- true: `1`, `t`, `true`
- false: `0`, `f`, `false`

For instrumented requests, operator precedence is:

```text
ci > agent > interactive > automated_unattributed
```

The bounded `operator` values are:

- `ci`: `Fly-Client-CI` is valid and true.
- `agent`: CI is not true and a valid agent declaration is present.
- `interactive`: CI is not true, no valid agent is present, and the
  interactive sentinel is true.
- `automated_unattributed`: the request is instrumented, but none of the
  preceding conditions apply.
- `uninstrumented`: the instrumentation sentinel is missing or invalid.

The bounded `agent` value is:

- the normalized agent name when it is in `markers.json`;
- `other` for a valid sanitized declaration not in `markers.json`;
- `none` when the declaration is missing or invalid, or when the request is
  uninstrumented.

CI precedence does not erase a valid agent value. This preserves aggregate
visibility into CI requests driven by known agents.

`Fly-Client-Parent` and `Fly-Client-Agent-Source` must not affect either
classification field.

## API route selection

The route selector receives:

- HTTP method;
- matched route template, if routing found one;
- raw request path;
- a service-owned list of tracked path prefixes.

If a route template is present, prefix selection must use the template. The
raw request path must not override a present template. This prevents a
catch-all route outside the selected API namespace from being counted as a
specific API route.

If no route template is present, the raw request path may be used only to
decide whether the request falls under a tracked prefix. It must never be
returned as a metric label.

Tracked route labels are:

```text
UPPERCASE_METHOD matched-route-template
UPPERCASE_METHOD unmatched
```

The method is trimmed and uppercased. An empty method becomes `UNKNOWN`.

Prefix matching occurs on path-segment boundaries. `/v1` matches `/v1` and
`/v1/...`, but not `/v10`. A trailing slash on a configured prefix is
equivalent to the same prefix without it. `/` selects every absolute path.

Requests outside the configured prefixes are not observed.

## Cardinality requirements

- Never place a raw request path in `api_route`.
- Never place an unknown caller-provided agent name in `agent`; use `other`.
- Keep `service` to one bounded value per service deployment.
- Do not add Parent or agent-source values as labels.
