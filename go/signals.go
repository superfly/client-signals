// Package clientsignals computes coarse, privacy-safe signals that help
// estimate whether a CLI process is being driven by a human or an AI agent.
//
// This package is intentionally self-contained: no dependencies beyond the
// standard library and golang.org/x/sys (used for syscall-based
// parent-process lookup on Darwin/Windows), so it can be used standalone.
package clientsignals

import "sync"

// Signals is the set of coarse, privacy-safe traffic-classification signals
// computed once per process.
//
// See docs/signals.md for the reasoning behind these fields, each one's
// known reliability caveats, and how they're meant to be combined — no
// single field here is sufficient on its own, and none should ever drive
// gating/enforcement decisions.
type Signals struct {
	// Interactive is true if the process's stdout appears to be attached to
	// a terminal.
	Interactive bool

	// Parent is a coarse bucket describing the immediate parent process.
	// Always one of "node", "python", "shell", or "other" — never a raw
	// process name.
	Parent string

	// Agent is the cooperative agent marker, e.g. "claude-code". Empty if no
	// agent was declared or detected.
	Agent string

	// AgentSource identifies how Agent was determined, e.g.
	// "env:FLY_INVOKED_BY" or "env:CLAUDECODE" — the matched variable name,
	// never its value. Empty if and only if Agent is empty.
	AgentSource string

	// CI is true when a CI environment is detected.
	CI bool
}

// Detect computes the current process's client signals fresh from the
// environment and file descriptors. It is pure and side-effect free (aside
// from reading process state); it does not cache its result — callers that
// want a single value for the lifetime of a process should cache it
// themselves.
func Detect() Signals {
	agent, source := detectAgent()

	return Signals{
		Interactive: isInteractive(),
		Parent:      parentBucket(),
		Agent:       agent,
		AgentSource: source,
		CI:          isCI(),
	}
}

var detectOnce = sync.OnceValue(Detect)

// DetectOnce returns the process-wide signals, computed once via Detect and
// cached for the lifetime of the process. Detection involves a
// parent-process lookup and environment scanning, so callers should fetch
// this once (e.g. at client-construction time) and reuse the result rather
// than calling it per request.
func DetectOnce() Signals {
	return detectOnce()
}

// Operator returns a single classification for the process's operator.
// Precedence: ci > agent > interactive > unknown.
//
// This is a convenience for consumers that want one label describing who is
// driving the process. The raw fields (CI, Agent, Interactive) remain
// available for callers that need finer-grained logic.
func (s Signals) Operator() string {
	switch {
	case s.CI:
		return "ci"
	case s.Agent != "":
		return "agent"
	case s.Interactive:
		return "interactive"
	default:
		return "unknown"
	}
}

// resetCachedForTest clears the cached signals so tests can exercise Detect
// against a freshly modified environment. Only for use in this package's
// own tests.
func resetCachedForTest() {
	detectOnce = sync.OnceValue(Detect)
}
