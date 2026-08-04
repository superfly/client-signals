# Agent markers: background and how to add new ones

This documents the reasoning behind the shared agent-marker table in
`spec/markers.json` and its language-specific mirrors — where it came
from, why each entry is shaped the way it is, and what future
agents/developers should check before adding to it. Runtime source files
only carry terse safety notes; the fuller "why" lives here so it doesn't
get lost.

## Where this came from

`client-signals` implements one part of a larger spec for estimating what
fraction of Fly CLI traffic (flyctl, sprites) is driven by AI coding agents
vs. typed by humans, for capacity planning, rate-limit/abuse policy, and
product decisions — **never** for per-request gating or enforcement. The
cooperative-agent marker is the most specific of the shared signals.
Interactivity and parent-process bucket are coarser. It's "cooperative"
because it only ever raises confidence — its *absence* is not evidence of a
human, since not every agent harness sets a recognizable marker.

## Precedence

1. `FLY_INVOKED_BY` — a public, documented env var any agent harness (ours
   or third-party) can set to self-declare, e.g. `FLY_INVOKED_BY=my-tool`.
   This is the only field on the wire that isn't from the fixed table
   below, so it's sanitized and length-capped before ever being emitted.
2. The `knownMarkers` table, first match wins.
3. The cross-tool `AGENT=<name>` convention (also sanitized the same way).

Detection is **passive and best-effort**: it confirms an agent when a
marker matches, but never proves a human when nothing matches.

## The table, and the confidence behind each entry

Confidence here reflects how reliably the marker reaches the process where
the CLI actually runs — it's not encoded anywhere in the code (the wire
format has no room for it, per the "coarse, not creepy" principle below),
but it's why some markers are `presence`-only and others require an exact
value, and it's useful context if a marker turns out to be noisier than
expected and needs reconsidering.

| Agent | Marker(s) | Kind | Confidence | Why |
|---|---|---|---|---|
| Claude Code | `CLAUDECODE=1` | exact | High | Set directly by the Claude Code process itself. |
| Claude Code | `CLAUDE_CODE_ENTRYPOINT` | presence | High | Also set directly by Claude Code (value varies: `cli`, `sdk-py`, `vscode`, …); presence alone is enough. |
| pi | `PI_CODING_AGENT=true` | exact | High | Set directly by the pi harness. |
| OpenClaw | `OPENCLAW_SHELL=exec` | exact | Med | Set by OpenClaw's exec wrapper; less certain to survive every subprocess boundary than a var the top-level process sets on itself. |
| OpenClaw | `OPENCLAW_CLI=1` | exact | High | Set directly by the OpenClaw CLI process. |
| Goose | `GOOSE_TERMINAL=1` | exact | High | Set directly by Goose. |
| Cross-tool convention | `AGENT=<name>` | presence + sanitized value | High where set | An informal convention (goose, amp, …); trusted like `FLY_INVOKED_BY` since the value is a self-declaration, so it's sanitized the same way rather than mapped through the fixed-tag table. |
| Hermes | `HERMES_SESSION_ID` | presence | Med | Value shape (`YYYYMMDD_HHMMSS_<hex>`) wasn't confirmed against the real variable name at spec time — treat as presence-only until reverified. |
| Codex | `CODEX_SANDBOX`, `CODEX_THREAD_ID` | presence | Med | Values are sandbox-profile names or UUIDs — not stable enough to match exactly, but presence itself is a reasonable signal. |
| Cursor | `CURSOR_TRACE_ID`, `CURSOR_AGENT` | presence | Med | Same reasoning as Codex. |
| Gemini CLI | `GEMINI_CLI` | presence | Med | |
| Kiro | `TERM_PROGRAM=kiro` | exact | Med | `TERM_PROGRAM` is a shared convention across terminal emulators/IDEs, so it's matched on an exact value rather than presence to avoid false positives from unrelated tools that also set `TERM_PROGRAM`. |
| Antigravity | `ANTIGRAVITY_AGENT` | presence | Med | |
| Augment | `AUGMENT_AGENT` | presence | Med | |
| Replit | `REPL_ID` | presence | Med | |
| OpenCode | `OPENCODE`, `OPENCODE_CALLER`, `OPENCODE_CLIENT` | presence | Med | |
| GitHub Copilot | `COPILOT_MODEL`, `COPILOT_ALLOW_ALL` | presence | Med | |
| Kilo Code | `KILO_PLATFORM=vscode` | exact | Low | Set by an editor extension, not confirmed to reach the shell the CLI actually runs in. |
| Grok Build | `GROK_AGENT=1` | exact | High | Set by Grok Build on the subprocesses its tools spawn — verified empirically against Grok Build 0.2.103, which exports `GROK_AGENT=1` to its bash tool from an otherwise clean environment. Matched on the exact value because the same name is *also* a documented user-facing setting (see below). |

**`GROK_AGENT` is dual-use, and the exact-value match is load-bearing.**
Grok Build documents `GROK_AGENT` as a user setting holding "custom agent
definition path or name" — the env form of its `--agent` flag. That form is
precisely the config-style variable this table is supposed to exclude: a human
can set `GROK_AGENT=my-reviewer` in a shell profile and forget it. The tool-set
marker is the literal string `1`, which is never a meaningful agent name or
path, so `exactValue: ["1"]` separates the two uses. Do not relax this entry to
`presence` — that would misclassify every session of any human who has
configured a custom Grok agent.

**Grok Build also sets `CI=true` on tool subprocesses.** It ships a bundle of
"make subprocesses non-interactive" variables (`CI=true`, `NO_COLOR=1`,
`PAGER=cat`, `GIT_TERMINAL_PROMPT=0`, …). Since operator precedence is
`ci > agent`, a CLI invoked from Grok's bash tool classifies as
`operator="ci"`, not `operator="agent"` — the `agent="grok"` label is still
preserved (see [request-metrics.md](../spec/request-metrics.md)), but the
"subtract CI before attributing the remainder to agents" approach in
[signals.md](signals.md) will subtract this traffic away. Treat `operator="ci"
+ agent="grok"` as agent traffic when reporting, not as CI. Other harnesses
may do the same; this is the first one confirmed to.

**Containerized/wrapped agents need no special rows.** E.g. an agent that
runs Claude Code inside a container already shows up as `CLAUDECODE=1`
without any extra entry; a wrapper that stamps no subprocess marker at all
is simply undetectable by this mechanism — that's an accepted gap, not a
bug to work around.

## What's deliberately *not* a marker

- **Config-style variables humans set by hand** — `OPENCLAW_HOME`,
  `HERMES_HOME`, `PICOCLAW_HOME`, `PI_CODING_AGENT_DIR`, `KILO_ORG_ID`,
  `AIDER_*`, etc. Their presence says nothing about how the CLI was
  invoked (a human can set these in their shell profile once and forget
  about them) — including them would silently misclassify ordinary human
  sessions as agent-driven forever after.
- **Secret-shaped variables** — anything token/key/credential-like (e.g.
  `COPILOT_GITHUB_TOKEN`, `*_API_KEY`, `*_TOKEN`). Never read, never
  forwarded, not even for presence-checking purposes.

## Privacy constraints that shape this table (don't relax these)

- **Approved values only.** `Agent` is always one of a known, finite tag
  set (`claude-code`, `goose`, …) or the sanitized self-declaration from
  `FLY_INVOKED_BY`/`AGENT` — never an arbitrary string pulled from
  whatever a matched variable happened to contain.
- **Presence, not values, for table-driven markers.** `AgentSource`
  records which variable matched (e.g. `env:CLAUDECODE`), never its
  value.
- **The litmus test for any new entry**: if the value you'd want to put on
  the wire varies per-user, per-machine, or per-repo (beyond a
  self-declared tool name), it doesn't belong in this table as-is — that's
  a bug, not a feature.

## Adding a new marker

1. Confirm the variable is set by the *tool itself* on the process where
   the CLI actually runs — not a config/install-time variable, not
   something a human sets by hand.
2. Decide `presence` vs `exactValue`: prefer `exactValue` when the
   variable name is a shared/generic convention that unrelated tools might
   also set (like `TERM_PROGRAM`); `presence` is fine when the variable
   name itself is tool-specific enough that only that tool would plausibly
   set it.
3. Never match on or forward anything secret-shaped.
4. Add a row to `spec/markers.json` and mirror it in each language
   package's dependency-free marker table.
5. Add or update fixture-driven tests in each package so the mirror stays
   aligned with `spec/markers.json`.
6. Update the table above with the same reasoning (kind + confidence +
   why), so the next person doesn't have to reconstruct it.

This list is expected to grow as new agent harnesses appear; there's no
formal "owner" process yet for reviewing additions — use judgment and the
litmus test above.
