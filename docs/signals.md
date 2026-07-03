# Signals: background and reliability caveats

This documents the reasoning behind the `Signals` struct and its four
fields (`signals.go`, `interactive.go`, `parent.go`, `ci.go`, and the agent
detection covered separately in [markers.md](markers.md)) — what each
signal is worth, its known failure modes, and how they're meant to be
combined. The struct/field doc comments cover the "what"; this covers the
"why" and "how reliable," which doesn't fit in a doc comment without
burying the actual API reference.

## Why these four fields, in this order

`Interactive` and `Parent` are coarse and generic; `Agent` is specific and
cooperative. That ordering matters: only `Agent` (and to a lesser extent
`CI`) can ever *confirm* something — `Interactive` and `Parent` are weak
priors that shift a probability, never proof. The whole point of this
package is to produce **an estimate with confidence**, not a per-request
classification — nothing here should ever be used to gate, block,
rate-limit, or make auth decisions. Combine multiple fields into a
probability; never treat one field alone as ground truth.

Every field is also constrained to a small, finite, pre-approved set of
values (or a sanitized self-declaration, in `Agent`'s case) — never an
arbitrary string pulled from local process/environment state. That's a
hard privacy constraint, not just a style choice: nothing in `Signals`
should vary in a way that's identifying per-user, per-machine, or per-repo.

## `Interactive`

Whether the process's stdout looks attached to a terminal.

**Caveat**: `Interactive=false` means "stdout is not a terminal," not "not
a human." Piped output, redirected input, and CI all look identical here —
a human piping output through `| less` or `| tee` looks the same as a
script. Treat this as "plausibly unattended," not "definitely automated."

**Implementation notes**:
- Checks `os.Stdout`, not `os.Stdin`. Rationale: the signal we actually
  want is "is a human plausibly watching this run," which stdout answers
  better — a human can pipe stdin from a file while still watching a TTY,
  but if stdout itself is redirected there's essentially never a human
  directly watching. Checking both and requiring both true is a reasonable
  alternative if stdout-only turns out to have too many false positives in
  practice (e.g. an agent wrapper that allocates a pty for stdout but
  drives stdin itself).
- Uses the `os.ModeCharDevice` bit from `Stat()`, not
  `golang.org/x/term.IsTerminal`. This is a cruder check (no
  `ioctl`/`GetConsoleMode`), traded off deliberately to keep this package
  dependency-free.

## `Parent`

A coarse bucket (`node`, `python`, `shell`, or `other`) describing the
immediate parent process — never a raw process name, by design (see the
privacy constraint above).

**This is the noisiest signal, in both directions. Treat it as a weak
prior, weighted higher for language runtimes than for shells, and never
rely on it alone:**

- **Shells are ambiguous both ways.** A shell parent can be a human at a
  prompt, a CI step, or an agent shelling out — `Parent=shell` alone tells
  you nothing about which.
- **Wrappers hide the real caller.** Package-manager runners, Makefiles,
  shell functions, version-manager shims, and git hooks all sit between
  the real invoker and this process, so the visible parent is often just
  tooling, not the thing that actually decided to run this command.
- **Fast agent loops can exit before we look**, leaving the OS init
  process as the visible parent — meaning this signal *undercounts* the
  most agent-heavy traffic, which is exactly the tail we care most about
  estimating.
- **Inside containers the process tree is shallow** and everything tends
  to look the same (`Parent=other` or a container entrypoint's shell).
  This case tends to co-occur with a datacenter-network signal the
  backend already has independently, so the two can be cross-checked
  server-side rather than trusted alone.

**Implementation notes**: parent-process name lookup never spawns a
subprocess (a real cost that was worth avoiding even though it only
happens once per process) — it reads `/proc/<ppid>/comm` on Linux, issues
a direct `sysctl` via `golang.org/x/sys/unix` on Darwin, and walks a
Toolhelp32 snapshot via `golang.org/x/sys/windows` on Windows. Whatever
that raw name is, `classifyParentName` collapses it into the finite bucket
set — an unrecognized or unavailable parent name always becomes `other`,
never propagated as-is.

## `Agent` / `AgentSource`

The cooperative marker — see [markers.md](markers.md) for the marker table
itself and how new ones get added.

**This one is one-directional**: its presence confirms an agent; its
*absence* is not evidence of a human. Not every agent harness sets a
recognizable marker (see "containerized/wrapped agents" in markers.md), so
`Agent == ""` just means "no marker recognized," not "human-driven."

## `CI`

A supporting bit — true when `CI` or `GITHUB_ACTIONS` is present in the
environment (presence-only: `CI=""` still counts, matching how some CI
systems set it). This isn't meant to classify human vs. agent by itself —
it exists so that CI traffic can be subtracted out *before* attributing
the remaining "automated" traffic to agents, since CI runs are automated
but not agent-driven.

## How the fields are meant to combine (server-side, informative here)

The actual bucketing/weighting happens on the backend, not in this
package, but the shape of what gets emitted is designed around this
intended interpretation:

- `Interactive=false` and no `Agent` → "automated, unattributed."
- `Agent` present → "agent: X" — treated as *confirmed* only when
  self-declared via `FLY_INVOKED_BY` (passive marker detection is weaker
  evidence than a direct self-declaration).
- `CI=true` is subtracted from the "automated" bucket before attributing
  anything to agents.
- `Parent` is weighted lower for shells than for language runtimes, and
  never used alone.

## Compute once, never per request

`Detect()` is pure and does the actual work (file/environment reads, the
parent-process lookup); `DetectOnce()` wraps it in `sync.OnceValue` so
repeated calls in the same process are free. Signal collection is
expensive enough (a syscall or `/proc` read, plus scanning ~20 env vars)
that it must never run per HTTP request — see `ClientSignalsTransport` in
`transport.go`, which computes this once at construction and reuses the
result for every request the transport forwards.
