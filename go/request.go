package clientsignals

import (
	"net/http"
	"strconv"
	"strings"
)

const (
	// RequestOperatorCI identifies instrumented requests made from CI.
	RequestOperatorCI = "ci"
	// RequestOperatorAgent identifies instrumented, non-CI requests with a
	// valid cooperative agent marker.
	RequestOperatorAgent = "agent"
	// RequestOperatorInteractive identifies instrumented, non-CI requests
	// whose stdout was attached to a terminal and had no agent marker.
	RequestOperatorInteractive = "interactive"
	// RequestOperatorAutomatedUnattributed identifies instrumented, non-CI,
	// non-interactive requests with no recognized agent marker.
	RequestOperatorAutomatedUnattributed = "automated_unattributed"
	// RequestOperatorUninstrumented identifies requests without a valid
	// Fly-Client-Interactive header.
	RequestOperatorUninstrumented = "uninstrumented"

	// RequestAgentNone is the bounded metric value used when no valid agent
	// marker was supplied.
	RequestAgentNone = "none"
	// RequestAgentOther is the bounded metric value used for valid sanitized
	// self-declarations that are not in the known marker table.
	RequestAgentOther = "other"
)

// RequestClassification is the bounded, server-side interpretation of incoming
// client-signal headers. Operator and Agent are safe to use as metric labels.
type RequestClassification struct {
	Operator string
	Agent    string
}

// ClassifyRequestHeaders returns bounded metric-label values for an incoming
// request. Fly-Client-Interactive is the instrumentation sentinel; Parent is
// deliberately ignored because parent-process lookup is not reliable enough
// for request classification.
//
// CI takes precedence over agent, which takes precedence over interactive.
// Agent is still preserved for CI requests so aggregate metrics can expose the
// CI+agent overlap.
func ClassifyRequestHeaders(header http.Header) RequestClassification {
	interactive, ok := parseRequestBool(header.Get(DefaultHeaderPrefix + "-Client-Interactive"))
	if !ok {
		return RequestClassification{
			Operator: RequestOperatorUninstrumented,
			Agent:    RequestAgentNone,
		}
	}

	agent := normalizeRequestAgent(header.Get(DefaultHeaderPrefix + "-Client-Agent"))
	ci, _ := parseRequestBool(header.Get(DefaultHeaderPrefix + "-Client-CI"))

	switch {
	case ci:
		return RequestClassification{Operator: RequestOperatorCI, Agent: agent}
	case agent != RequestAgentNone:
		return RequestClassification{Operator: RequestOperatorAgent, Agent: agent}
	case interactive:
		return RequestClassification{Operator: RequestOperatorInteractive, Agent: agent}
	default:
		return RequestClassification{
			Operator: RequestOperatorAutomatedUnattributed,
			Agent:    agent,
		}
	}
}

// TrackedRoute returns the bounded route metric label for a request and
// whether it should be recorded. A matched route template is preferred. For an
// unmatched request, requestPath is used only to determine whether the request
// targeted a tracked prefix and is never included in the returned label.
func TrackedRoute(method, routeTemplate, requestPath string, prefixes []string) (string, bool) {
	method = strings.ToUpper(strings.TrimSpace(method))
	if method == "" {
		method = "UNKNOWN"
	}

	if routeTemplate != "" {
		if matchesRoutePrefix(routeTemplate, prefixes) {
			return method + " " + routeTemplate, true
		}

		return "", false
	}

	if matchesRoutePrefix(requestPath, prefixes) {
		return method + " unmatched", true
	}

	return "", false
}

func normalizeRequestAgent(raw string) string {
	agent, ok := sanitizeInvokedBy(raw)
	if !ok {
		return RequestAgentNone
	}

	for _, marker := range knownMarkers {
		if marker.agent == agent {
			return agent
		}
	}

	return RequestAgentOther
}

func parseRequestBool(raw string) (bool, bool) {
	if raw == "" {
		return false, false
	}

	value, err := strconv.ParseBool(strings.TrimSpace(raw))

	return value, err == nil
}

func matchesRoutePrefix(path string, prefixes []string) bool {
	for _, prefix := range prefixes {
		prefix = strings.TrimSuffix(prefix, "/")
		if prefix == "" || prefix == "/" {
			if strings.HasPrefix(path, "/") {
				return true
			}

			continue
		}
		if path == prefix || strings.HasPrefix(path, prefix+"/") {
			return true
		}
	}

	return false
}
