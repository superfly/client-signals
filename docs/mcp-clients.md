# MCP clients: background and how to add new rules

This documents the reasoning behind the shared MCP client rule table in
`spec/mcp-clients.json` and its language-specific mirrors: where each rule
came from, how confident we are in it, what was left out on purpose, and what
to check before adding a rule. The classification contract itself lives in
[request-metrics.md](../spec/request-metrics.md#mcp-client-identity-opt-in-inferred);
this file covers the "why".

## Where this came from

MCP clients connecting to a Fly-hosted MCP server never send `Fly-Client-*`
headers, so every MCP request classified as `uninstrumented/none`. They do
identify themselves, though, through three inputs a server can already see:

- `clientInfo.name` in `initialize` params, and from protocol `2026-07-28`
  also in `_meta["io.modelcontextprotocol/clientInfo"]` on every request;
- the HTTP `User-Agent`;
- `X-Anthropic-Client`, sent by Anthropic's claude.ai connector relay.

The rule table maps those inputs onto a small set of bounded client labels.
Unlike the cooperative agent markers in [markers.md](markers.md), these values
are *inferred* from strings the client chose, not self-reported for
client-signals. That's why classification only runs on routes a service
declares as MCP routes, and why an unrecognized User-Agent alone never
produces a client.

Most rules below were checked against shipped binaries, source at a pinned
commit, or captured traffic, and a second, independent pass then confirmed or
corrected each string. Rules marked Low rest on weaker evidence, such as
third-party client registries, gateway analytics summaries, or another
project's seed data, and the table says which. They were kept on purpose
because the string is specific to one product. Strings that could not be tied
to a product at all were left out.

## Labels

Labels reuse the `markers.json` agent names when the product is the same
(`claude-code`, `codex`, `cursor`, `copilot`, `gemini-cli`, `goose`, `grok`,
`opencode`, `kilo-code`, `kiro`, `augment`, `pi`, `openclaw`, `hermes`). New
labels are added only for clients that have no marker: `claude-ai`,
`anthropic-api`, `chatgpt`, `openai-api`, `openai`, `vscode`, `zed`, `cline`,
`roo-code`, `continue`, `amp`, `junie`, `jetbrains-ai`, `warp`, `librechat`.

Server-side request classification treats the union of both sets as the known
agent vocabulary, so `Fly-Client-Agent: zed` reports `zed`, not `other`.

## Weak rules

A rule marked `weak` names a string that more than one product sends:

- `Anthropic/ClaudeAI` is sent by claude.ai chat and also by Claude Code and
  Cowork when they go through the claude.ai relay. PostHog's MCP analytics
  notes that rows with only this name "often self-report a wrong
  clientInfo.name (Claude Code as `Anthropic/ClaudeAI`)".
- A bare `Anthropic` name was logged once from the same relay.
- `openai-mcp`, as a bare User-Agent or clientInfo name, is OpenAI's shared
  hosted client. It covers ChatGPT, Codex through the apps platform, Agent
  Builder and the Responses API, and only the User-Agent parenthetical tells
  them apart.

Weak rules are checked last, after every strong rule on every input. A
specific identity therefore always wins over a pooled one. For example,
`openai-mcp/1.0.0 (Codex)` with clientInfo `openai-mcp` reports `codex`, and a
bare `openai-mcp/1.0.0` with clientInfo `openai-mcp (Responses API)` reports
`openai-api`. A weak match is still a match, so a request that only carries a
pooled name is labelled rather than falling through to `other`.

## The table, and the confidence behind each entry

Confidence reflects how well the exact string is evidenced and how specific
it is to one product. Like markers, it isn't encoded anywhere in the code.
It's here so that a rule that turns out to be noisy can be reconsidered with
the original evidence in hand.

"First-party" means the shipped binary or the vendor's own source, read
directly. "Third-party" means another project's logs, tests or registry.

### `X-Anthropic-Client` (exact, after removing `-`, `_` and spaces)

| Label | Value | Confidence | Evidence and caveats |
|---|---|---|---|
| `claude-code` | `claudecode` | Med | Sent as `ClaudeCode` when Claude Code uses a claude.ai-hosted connector through Anthropic's relay (anthropics/claude-ai-mcp#1171, #1139). PostHog's harness records both `ClaudeCode` and `claude-code` spellings, which is why `-`, `_` and spaces are removed. Undocumented by Anthropic; third-party logs only. Checked before the UA because the relay always sends `Claude-User` and often the pooled `Anthropic/ClaudeAI` name. |
| `claude-ai` | `claudeai` | Med | claude.ai chat through the relay (#1171, #1139, #886). Third-party logs only. |
| `claude-ai` | `claudeartifacts` | Med | Artifacts' MCP capability (#1171 table). Third-party logs only. |
| `claude-ai` | `cowork` | Med | Cowork and Desktop through the relay (#886, #1139). PostHog's client detection notes that Claude desktop chat reports `Cowork`. |

Unknown values (for example `ClaudeDesign`, or the `claude-cli-design-*`
values Claude Code sends only to Anthropic's own endpoints) are ignored, and
classification falls through to the User-Agent.

### `User-Agent` (token, unless noted)

| Label | Value | Confidence | Evidence and caveats |
|---|---|---|---|
| `claude-code` | `claude-code` | High | First-party: the `@anthropic-ai/claude-code` 2.1.309 binary builds `claude-code/<ver> (<entrypoint>[, agent-sdk/<v>][, client-app/<app>])` for every MCP transport. Covers the CLI (`cli`, `sdk-cli`), the TS and Python Agent SDKs (`sdk-ts`, `sdk-py`), the VS Code extension (`claude-vscode`) and Claude Code inside Claude Desktop. User-configured MCP server headers are applied after the UA and can replace it, so clientInfo `claude-code` is the fallback. |
| `claude-ai` | `claude-user` | Med | claude.ai relay traffic logs bare `Claude-User` (#886, #1171, #1139). Third-party logs. Claude Code's own WebFetch tool also sends `Claude-User (<platform>; +https://support.anthropic.com/)`, which is one reason MCP classification must be scoped to MCP routes. |
| `codex` | `codex-mcp-client` | High | First-party: `codex-rs/rmcp-client/src/utils.rs` sets `codex-mcp-client/<CARGO_PKG_VERSION>` on streamable HTTP and OAuth requests from rust-v0.146.0. Shared by the Codex CLI, `codex exec`, the IDE extension and the desktop app. Prerelease builds send versions such as `codex-mcp-client/0.163.0-alpha.11.1`. Earlier releases send no UA and fall back to clientInfo. |
| `chatgpt` | `openai-mcp` + `(chatgpt)` | Med | `openai-mcp/1.0.0 (ChatGPT)` from PostHog's production client detection and tests. No OpenAI documentation. |
| `codex` | `openai-mcp` + `(codex)` | Med | `openai-mcp/1.0.0 (Codex)` in several independent real access logs (ForgeLex Cloud Run logs, Pexafy production counts) and PostHog tests. The string is well evidenced, but which Codex surface sends it isn't: it is Codex reaching a server through OpenAI's hosted connector platform, not the local Codex CLI. |
| `openai-api` | `openai-mcp` + `(responses api)` | Med | `openai-mcp/1.0.0 (Responses API)` in a logged Azure OpenAI hosted MCP request (nhcloud/responses-api) and PostHog seed data. |
| `openai-api` | `openai-mcp` + `(agent builder)` | Low | `openai-mcp/1.0.0 (Agent Builder)` only in PostHog seed data and harness mappings. No captured traffic. |
| `openai` (weak) | `openai-mcp` | Med | Bare `openai-mcp/1.0.0` in independent real logs (plamotrack, davisanc). It can't be tied to one surface. PostHog labels it "OpenAI", and Pexafy attributes most of it to ChatGPT. Weak, so a surface parenthetical or a specific clientInfo name wins. |
| `vscode` | `visual studio code` | High | First-party: `extHostMcp.ts` sets `user-agent: ${product.nameLong}/${product.version}` after user-configured headers, so it can't be overridden. Stable gives `Visual Studio Code/1.141.1`. This identifies the VS Code MCP host, not Copilot: any extension using the host sends the same value. Insiders (`Visual Studio Code - Insiders/…`) also matches the token but was not verified. |
| `cursor` | `cursor` | High | First-party: the Cursor editor's `cursor-mcp` extension sends `Cursor/<version> (<platform> <arch>)`, and the Cursor agent CLI sends `Cursor/1.0.0`. Both let user headers replace the UA. `CursorPluginInstaller` is a non-MCP UA in the same bundle and does not match the token. |
| `copilot` | `copilot` | High | First-party: `@github/copilot` 1.0.62 builds `copilot/<ver> (<platform> <node version>) term/<TERM_PROGRAM>`, with `client/<name> ` inside the parenthetical for SDK sessions. Read from source, not captured on the wire. 1.0.64 and later ship a compressed binary that couldn't be re-checked. A user-set UA suppresses it. |
| `copilot` | `githubcopilot` | High | First-party: `@github/copilot-language-server` 1.560.0 sets `GithubCopilot/<ver>` on MCP HTTP traffic. This covers Copilot in JetBrains, Xcode, Eclipse, Visual Studio and Vim, whose clientInfo name is a per-editor template (see exclusions). When the editor's own HTTP stack makes the request, the editor could alter the UA. |
| `zed` | `zed` | High | First-party: Zed sets `Zed/<app version> (<os>; <arch>)`, e.g. `Zed/1.27.0 (macos; aarch64)`, as the default UA of its HTTP client. User-configured static headers can replace it. |
| `goose` | `goose` | High | First-party: goose's streamable HTTP transport sets `goose/<CARGO_PKG_VERSION>`. Under ACP, goose takes the ACP host's clientInfo name, so the UA is the better signal there. |
| `grok` | `grok-cli` | High | First-party: Grok Build sets `grok-cli/<version>` (bare `grok-cli` for Figma hosts) only when the request has no UA yet. |

### `clientInfo.name` (exact, unless noted)

`clientInfo` is checked after the UA so that `initialize` and later
stateless `tools/call` requests get the same label. On protocol versions up
to `2025-11-25`, those later requests carry a UA but no clientInfo.

| Label | Value | Confidence | Evidence and caveats |
|---|---|---|---|
| `claude-code` | `claude-code` | High | First-party: the 2.1.309 binary builds `{name:"claude-code",title:"Claude Code",...}` for every transport. |
| `claude-ai` | `claude-ai` | High | Claude Desktop's local stdio client (`claude-ai` 0.1.0, from a Desktop log in anthropics/claude-code#65643 and from LumeWeb/canimcp). It was also logged from the claude.ai connector (#792). Over HTTP it most often arrives through `mcp-remote`, whose suffix is stripped. |
| `claude-ai` (weak) | `anthropic/claudeai` | High string, pooled | Logged initialize payloads (#792, #1027). Pooled with Claude Code and Cowork through the relay (see [Weak rules](#weak-rules)). |
| `claude-ai` (weak) | `anthropic` | Low | A single log line in #792 from the claude.ai relay. Pooled and generic, so weak. |
| `anthropic-api` | `anthropic/api` | Low | Anthropic Messages API MCP connector. Three independent third-party registries agree, and one public project observed it in its gateway analytics. No raw payload and no Anthropic documentation. The UA is unknown. |
| `codex` | `codex-mcp-client` | High | First-party: `codex-rs/codex-mcp/src/rmcp_client.rs` sets `Implementation::new("codex-mcp-client", ...)`. This is the only identity for Codex releases before the UA was added. |
| `openai-api` | `openai-mcp (responses api)` | Low | One logged initialize from Azure OpenAI's hosted MCP. A second third-party capture (jmrplens/gitlab-mcp-server#1044) says the same. |
| `openai` (weak) | `openai-mcp` | Med | Pooled hosted OpenAI client name (canimcp, AgentDocker, PostHog). Its tools/call requests carry no clientInfo, so the UA usually decides. |
| `vscode` | `visual studio code` | High | First-party: `clientInfo: { name: productService.nameLong }`. Exact, so `Code - OSS` and forks with their own `nameLong` stay `other`. |
| `copilot` | `github-copilot-developer` | High | First-party in `@github/copilot` 1.0.62, and logged from a Copilot coding agent run. Shared by the CLI, the coding agent and other hosts (github/copilot-cli#2107), so it only says "a Copilot agent host". |
| `cursor` | `cursor-vscode` | High | First-party: Cursor editor's `cursor-mcp` extension. Forks of Cursor could share it. |
| `cursor` | `cursor` | High | First-party: the Cursor agent CLI sends `Cursor`, and its `2026-07-28` `_meta` shim falls back to lowercase `cursor`. Matching is case-insensitive, so both map here. |
| `zed` | `zed` | High | First-party: `crates/context_server` sets `name: "Zed"`. |
| `jetbrains-ai` | `jetbrains-ai-assistant-client` | High | First-party: `ml-llm` plugin bytecode, and a logged Rider initialize (MicrosoftDocs/mcp#39). The IDE (IDEA, Rider, PyCharm, …) can't be told apart. |
| `junie` | `junie-client` | High | First-party: Junie CLI 3110.7 bytecode. The IDE plugin probably sends the same, but that is inferred. |
| `gemini-cli` | `gemini-cli-mcp-client` | High | First-party: `packages/core/src/tools/mcp-client.ts`. Gemini sets no UA. The IDE-companion names `streamable-http-client`/`stdio-client` are local only and not matched. |
| `goose` | `goose-cli`, `goose-desktop` | High | First-party: `crates/goose/src/agents/agent.rs`. |
| `opencode` | `opencode` | High | First-party: `packages/core/src/mcp/client.ts` and the OAuth probe initialize. |
| `cline` | `cline` | High | First-party: the VS Code extension's `McpHub` sends `Cline`. |
| `cline` | `@cline/core` | High | First-party: the Cline SDK and CLI default when no client name is set. SDK embedders can set their own name, which then reports `other`. |
| `roo-code` | `roo code` | High | First-party: Roo Code's `McpHub` sends `Roo Code`. |
| `kilo-code` | `kilo`, `kilo code` | High | First-party: current Kilo (CLI and the extensions built on it) sends `kilo`. The archived legacy extension sends `Kilo Code`. Exact only, because `kilo` is short. |
| `continue` | `continue-client`, `continue-cli-client` | High | First-party: IDE extensions and the `cn` CLI, respectively. Both are listed because neither is a prefix of the other. |
| `kiro` | `q dev cli` | High | First-party: Kiro CLI 2.33.1 binary and the Amazon Q Developer CLI source both send `Q DEV CLI`, so the label also covers legacy Q CLI. The Kiro IDE's name is unknown. |
| `augment` | `augment-mcp-client` | High | First-party: the Auggie CLI 0.36.0 bundle. Augment's editor extensions weren't checked. |
| `amp` | `amp-mcp-client` | High | First-party: the Amp CLI (readable bundle and current binary). The Amp editor extension wasn't checked. |
| `warp` | `dev.warp.` (prefix) | High | First-party: `crates/mcp/src/runtime.rs` sends the channel app id. Logged values include `dev.warp.Warp-Stable` and `dev.warp.Warp`, and source shows `dev.warp.WarpOss` and `dev.warp.WarpTui`. Preview and Dev ids live in a private repo, so a prefix covers them. |
| `warp` | `warp` | Med | Legacy builds from mid-2025, from one logged payload (warpdotdev/warp#6798). |
| `librechat` | `@librechat/api-client` | High | First-party: `packages/api/src/mcp/connection.ts`. One identity covers every user of a LibreChat instance. |
| `grok` | `grok-shell-` (prefix) | High | First-party: Grok Build sends `grok-shell-<server_name>`. The suffix is the server name the user chose and is never stored or emitted. |
| `pi` | `pi` | High | First-party: pi's coding agent MCP runtime. Exact only, because `pi` is short. |
| `openclaw` | `openclaw-` (prefix) | High | First-party: the agent runtime sends `openclaw-bundle-mcp`, the browser extension sends `openclaw-browser`, and the QA suite sends `openclaw-qa-suite`. |
| `hermes` | `hermes-agent` | High | First-party: `tools/mcp_tool_transport.py`. |

## What's deliberately *not* matched

Requests that only carry one of these names classify as `mcp/other` when they
send a clientInfo name, and as `uninstrumented/none` otherwise:

- **SDK defaults and libraries**: `mcp` (official Python SDK, FastMCP,
  OpenAI Agents SDK for Python, LangChain Python), `rmcp` (official Rust SDK),
  `ai-sdk-mcp-client` (Vercel AI SDK) and `@langchain/mcp-adapters`. Any
  application built on these SDKs sends the same name, so the name says
  nothing about the product.
- **Library default User-Agents**: `node`, `undici`, `node-fetch`,
  `python-httpx/…`, `python-httpx2/…`, `Go-http-client/…`, `Bun/…`,
  `ktor-client` and `curl/…`. Many of the matched clients set no UA, so their
  requests carry one of these. They are never matched on their own.
- **Debugging and proxy tooling**: MCP Inspector (`mcp-inspector`,
  `inspector-cli`, `inspector-tui`, `inspector-client`), `docker-mcp-gateway`,
  Smithery (`@smithery/cli`), standalone `mcp-remote`, and flyctl's
  `fly mcp proxy` (`FlyMCP Proxy Client` in relay mode, UA
  `mcp-bridge-client` in passthru mode). These are tools, not agents, and a
  gateway hides the real client behind it.
- **`mcp-remote` itself**, when used as a bridge. It renames the downstream
  client to `<name> (via mcp-remote <version>)`. Normalization strips that
  suffix and classifies the downstream name instead.
- **Windsurf / Devin**: `windsurf-client` and `Windsurf` appear only in
  third-party registries. The literal isn't in the current Windsurf (Devin)
  language server binary, so the name couldn't be verified.
- **Visual Studio**: GitHub Copilot agent mode in Visual Studio sends an
  unknown clientInfo name. If it uses the Copilot language server, the
  `GithubCopilot/` UA identifies it.
- **Copilot editor templates**: the Copilot language server sends
  `<editor>/<plugin>` (for example `JetBrains-IU/copilot-intellij`). There's
  no suffix match kind, and the `GithubCopilot/` UA already covers it.
- **Secondary names from matched products**: `Anthropic/Toolbox` (only
  mentioned in prose, never logged), Claude Desktop Cowork's
  `local-agent-mode-<server>` (the suffix is the user's server name),
  `kilo-debug` (Kilo's `mcp debug` command), `hermes-probe` (Hermes'
  content-type preflight), `copilot-cli` (the Copilot CLI's local IDE bridge)
  and `pi-agent-example`.
- **Claude Code entrypoint surfaces**: the UA parenthetical (`cli`, `sdk-ts`,
  `claude-vscode`, `claude-desktop`, …) can distinguish surfaces, but it
  also carries arbitrary user-set values. Everything maps to `claude-code`.
- **Scanner and browser User-Agents**: MCP registry bots, generic crawlers and
  browsers hitting `/mcp` send no clientInfo and match no UA rule, so they
  stay out of the `mcp` operator.

## Never read

These are visible to an MCP server but are never inputs to classification,
not even as presence checks:

- `Authorization` and every other credential or secret-shaped header.
- `X-OpenAI-Session`, `X-OpenAI-Subject` and `openai/*` `_meta` keys. These
  are anonymized per-user and per-conversation identifiers.
- Per-session identifiers such as `Mcp-Session-Id`, Codex's
  `x-codex-turn-metadata`, opencode's `ai.opencode/sessionID` and Grok's
  `X-Grok-Agent-ID`.
- The version, title and description fields of `clientInfo`.

## Privacy constraints that shape this table (don't relax these)

- **Labels only.** The classifier returns a label from the table, `other` or
  nothing. It never returns the User-Agent, the clientInfo name or any part
  of them: not the version, not a `grok-shell-` server name, not a
  `client/<name>` Copilot SDK tag.
- **Unknown names collapse to `other`.** A clientInfo name the table doesn't
  know signals that the table needs extending. Recording the name itself is
  for a deliberate, short-lived investigation, never a metric label.
- **Never for gating.** Every input here is chosen by the client and is
  trivially spoofed. These labels are for aggregate reporting only.

## Adding a new rule

1. Get the exact string from the product itself: a shipped binary, source at
   a pinned commit, or a captured request. Registries and blog posts are
   leads, not evidence. Record where it came from.
2. Make sure the string identifies one product. Strings sent by several
   products (SDK defaults, library UAs, shared hosted clients) either stay
   unmatched or become a `weak` rule.
3. Pick the field. Prefer the UA when the product sets a distinctive one,
   because the UA arrives on every request. Add the clientInfo name as well,
   because the UA is often user-overridable and absent over stdio bridges.
4. Pick the kind. Use `exact` by default, and always for short names like
   `pi` or `kilo`. Use `token` for User-Agents. Use `prefix` only for
   separator-terminated families such as `dev.warp.` or `grok-shell-`. Add
   `contains` to refine a shared token by its parenthetical, and place the
   refined row before the generic one.
5. Store `value` already normalized: lowercase, and for `vendorClient` with
   `-`, `_` and spaces removed.
6. Reuse a `markers.json` agent name when the product already has one. A new
   label must be lowercase and pass agent sanitization (`[a-z0-9][a-z0-9-]*`,
   at most 64 bytes).
7. Never match on, or read, anything secret-shaped or per-user.
8. Add the row to `spec/mcp-clients.json`, mirror it in the Go and Elixir rule
   tables, and add at least one fixture to `spec/mcp-client-fixtures.json`
   using the real string, plus a boundary negative for short values.
9. Update the tables above with the evidence, confidence and caveats.
