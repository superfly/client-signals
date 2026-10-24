# Server-side request metric contract

This document defines the shared, language-neutral contract for classifying
incoming `Fly-Client-*` headers, inferring MCP client identity on MCP routes,
and selecting bounded route labels. Implementations may expose different
APIs, but must produce the results in `request-classification-fixtures.json`
and `route-fixtures.json`. Implementations that offer MCP classification must
also produce the results in `mcp-client-fixtures.json`.

This contract is for aggregate observability only. Client signals are
self-reported and must not be used for authentication, authorization,
rate-limiting, enforcement, or other per-request trust decisions.

## Canonical counter

Consuming services should expose one Prometheus counter:

```text
fly_client_signals_requests_total{
  service,
  route,
  operator,
  agent
}
```

The Go implementation provides a Prometheus collector, and the Elixir
implementation provides a telemetry event plus PromEx plugin for this counter.
Metric registration, the bounded `service` value, the route-template provider,
and the tracked route prefixes belong to each consuming service.

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
- `mcp`: only from MCP classification (see below). The sentinel is missing or
  invalid, and the request carries a recognizable MCP client identity.

The bounded `agent` value is:

- the normalized agent name when it is in the known agent vocabulary: the
  `agent` names in `markers.json` together with the `client` labels in
  `mcp-clients.json`;
- `other` for a valid sanitized declaration not in that vocabulary;
- `none` when the declaration is missing or invalid, or when the request is
  uninstrumented.

CI precedence does not erase a valid agent value. This preserves aggregate
visibility into CI requests driven by known agents.

`Fly-Client-Parent` and `Fly-Client-Agent-Source` must not affect either
classification field.

## MCP client identity (opt-in, inferred)

MCP clients do not send `Fly-Client-*` headers, so without this section all
MCP traffic is `uninstrumented/none`. They do identify themselves through
`clientInfo.name`, the `User-Agent`, and (for Anthropic's claude.ai relay)
`X-Anthropic-Client`. MCP classification maps those onto a bounded client
label using the rule table in `mcp-clients.json`. The rationale and evidence
for each rule live in [docs/mcp-clients.md](../docs/mcp-clients.md).

### Route scoping

MCP classification is opt-in and must only be applied to routes the
consuming service declares as MCP routes. Some of the strings it recognizes
are also sent by non-MCP traffic. For example, `Claude-User` is the claude.ai
relay's User-Agent and also Claude Code's WebFetch User-Agent. Requests on
other routes keep the plain classification above.

### Request classification on MCP routes

1. If `Fly-Client-Interactive` is a supported boolean, the result is the
   plain classification above, unchanged. Self-report always wins.
2. Otherwise, if the MCP client classifier returns a client, the result is
   `{"operator": "mcp", "agent": <client>}`, where `<client>` is a label from
   `mcp-clients.json` or `other`.
3. Otherwise, the result is `uninstrumented/none`.

`Fly-Client-Agent`, `Fly-Client-CI`, and the other `Fly-Client-*` headers are
ignored in step 2, as they are for any uninstrumented request.

### Inputs and normalization

The classifier takes three inputs:

- `vendorClient`: the `X-Anthropic-Client` header;
- `userAgent`: the `User-Agent` header;
- `clientName`: `clientInfo.name`, supplied by the caller. It comes from
  `_meta["io.modelcontextprotocol/clientInfo"].name` on any request (protocol
  `2026-07-28`), or from `params.clientInfo.name` on `initialize`.

Normalization is byte-oriented and identical in every implementation:

1. Trim leading and trailing ASCII whitespace.
2. Keep at most the first 256 bytes.
3. Lowercase ASCII `A`-`Z` only. Other bytes are left untouched.
4. `clientName` only: if it contains ` (via mcp-remote`, cut it at that index
   and trim ASCII whitespace again. `mcp-remote` appends
   ` (via mcp-remote <version>)` to the downstream client's name.
5. `vendorClient` only: remove every `-`, `_`, and space, so `ClaudeCode`,
   `claude-code`, and `claude_code` all become `claudecode`.

An input that is empty after normalization is absent.

### Rules and match kinds

Each rule has a `client` label, a `field` (`vendorClient`, `userAgent`, or
`clientName`), a `kind`, a `value` stored already normalized, an optional
`contains` substring, and an optional `weak` flag (default `false`):

- `exact`: the input equals `value`.
- `prefix`: the input starts with `value`. Used only for
  separator-terminated families such as `dev.warp.` and `grok-shell-`.
- `token`: the input equals `value`, or starts with `value` followed by one
  of `/`, space, `(`, or `;`. `cursor/1.0` matches `cursor`, and
  `cursorish/1.0` does not.
- `contains`: when present, the input must also contain this substring.

### Precedence

Rules are evaluated in one deterministic pass. Within a tier, the first
matching rule in table order wins.

1. First non-weak `vendorClient` match: source `vendor_header`.
2. First non-weak `userAgent` match: source `user_agent`.
3. First non-weak `clientName` match: source `client_info`.
4. First weak `userAgent` match, then first weak `clientName` match, with
   the source of the matching field.
5. A present `clientName` that matched nothing: client `other`, source
   `client_info`. Only real MCP clients send `clientInfo`, so this means the
   table needs extending.
6. Otherwise: no client (`""`), source `none`.

An unrecognized User-Agent or vendor header alone never produces a client.
That keeps bots, scanners, browsers, and `curl` hitting an MCP route out of
the `mcp` operator.

The User-Agent is checked before `clientName` so that `initialize` and later
stateless requests from the same client get the same label. A user-overridden
User-Agent usually matches nothing and falls through to `clientName`.

The source is for span attributes and debugging only. It is not a metric
label.

### Stateless caveat

On protocol versions up to `2025-11-25`, `clientInfo` is only sent on
`initialize`, and a stateless server has no session to carry it forward.
Clients that set a distinctive User-Agent are identified on every request.
Clients that don't (Gemini CLI, OpenCode, Cline, pi, and others that send a
library default such as `node` or `Bun/<version>`) are only identified on
`initialize`. Their later requests are `uninstrumented/none`, until they send
`_meta` clientInfo with protocol `2026-07-28`. Compare `mcp` counts across
clients by `initialize` volume, not by raw request totals.

### Reading the results

The effective agent of a request is its `agent` label whenever `operator` is
`agent`, `ci`, or `mcp`. `mcp` means the agent label was inferred from
client-chosen strings, not self-reported through `Fly-Client-*` headers. It
is weaker evidence than `agent`, but it covers clients that will never be
instrumented. `mcp/other` means a real MCP client the table does not know
yet.

These labels are for aggregate reporting only. Like every other input here,
they are trivially spoofed and must never be used for authentication,
authorization, rate-limiting, or any other per-request decision.

## Route selection

The route selector receives:

- HTTP method;
- matched route template, if routing found one;
- raw request path;
- a service-owned list of tracked path prefixes.

If a route template is present, prefix selection must use the template. The
raw request path must not override a present template. This prevents a
catch-all route outside the selected namespace from being counted as a
specific tracked route.

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

- Never place a raw request path in `route`.
- Never place an unknown caller-provided agent name in `agent`; use `other`.
- Never place a raw User-Agent, `X-Anthropic-Client` value, or
  `clientInfo` name, or any part of one, in a label or span attribute. Only
  the bounded client label and source may be recorded.
- Never read secret-shaped or per-user MCP inputs, such as `Authorization`,
  `X-OpenAI-Session`, `X-OpenAI-Subject`, or `openai/*` `_meta` keys.
- Keep `service` to one bounded value per service deployment.
- Do not add Parent or agent-source values as labels.
