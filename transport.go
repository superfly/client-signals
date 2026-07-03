package clientsignals

import (
	"fmt"
	"net/http"
	"strconv"
)

// DefaultHeaderPrefix is the header-name prefix WrapTransport uses when no
// other prefix is configured: "Fly", giving Fly-Client-Interactive,
// Fly-Client-Parent, etc. Callers outside Fly.io can use
// WrapTransportWithPrefix to substitute their own.
const DefaultHeaderPrefix = "Fly"

// userAgentSuffix returns the human-readable
// "(interactive=...; parent=...; agent=...)" token to append to a
// User-Agent string.
func userAgentSuffix(s Signals) string {
	suffix := fmt.Sprintf("interactive=%t; parent=%s", s.Interactive, s.Parent)
	if s.Agent != "" {
		suffix += "; agent=" + s.Agent
	}

	return "(" + suffix + ")"
}

// headersFor returns the {prefix}-Client-* header names and values for s,
// computed once so RoundTrip never has to.
func headersFor(prefix string, s Signals) map[string]string {
	h := map[string]string{
		prefix + "-Client-Interactive": strconv.FormatBool(s.Interactive),
		prefix + "-Client-Parent":      s.Parent,
	}
	if s.Agent != "" {
		h[prefix+"-Client-Agent"] = s.Agent
		h[prefix+"-Client-Agent-Source"] = s.AgentSource
	}
	if s.CI {
		h[prefix+"-Client-CI"] = "true"
	}

	return h
}

// ApplyHeaders sets the Fly-Client-* headers on header directly, for
// callers that need to attach client signals to something other than an
// http.Request going through an http.RoundTripper — e.g. a WebSocket
// handshake's header, built and sent outside of net/http's Client/Transport
// machinery entirely. Uses DefaultHeaderPrefix ("Fly").
func (s Signals) ApplyHeaders(header http.Header) {
	s.ApplyHeadersWithPrefix(header, DefaultHeaderPrefix)
}

// ApplyHeadersWithPrefix is like ApplyHeaders but lets callers outside
// Fly.io substitute their own header prefix, matching
// WrapTransportWithPrefix's prefix for the same Signals value.
func (s Signals) ApplyHeadersWithPrefix(header http.Header, prefix string) {
	for k, v := range headersFor(prefix, s) {
		header.Set(k, v)
	}
}

// ClientSignalsTransport wraps an http.RoundTripper, attaching the
// {prefix}-Client-* headers and appending the client-signals token to the
// existing User-Agent header on every outgoing request.
//
// Construct one via Signals.WrapTransport or Signals.WrapTransportWithPrefix.
// RoundTrip does no detection work itself — it only applies the values
// already computed when the transport was built.
type ClientSignalsTransport struct {
	InnerTransport http.RoundTripper

	headers  map[string]string
	uaSuffix string
}

// WrapTransport wraps inner in a *ClientSignalsTransport that attaches s to
// every request the returned transport forwards, using DefaultHeaderPrefix
// ("Fly-Client-*").
func (s Signals) WrapTransport(inner http.RoundTripper) *ClientSignalsTransport {
	return s.WrapTransportWithPrefix(inner, DefaultHeaderPrefix)
}

// WrapTransportWithPrefix is like WrapTransport but lets callers outside
// Fly.io substitute their own header prefix (e.g. "Acme" for
// Acme-Client-Interactive, Acme-Client-Parent, ...) instead of the "Fly"
// default. prefix must not be empty.
func (s Signals) WrapTransportWithPrefix(inner http.RoundTripper, prefix string) *ClientSignalsTransport {
	return &ClientSignalsTransport{
		InnerTransport: inner,
		headers:        headersFor(prefix, s),
		uaSuffix:       userAgentSuffix(s),
	}
}

func (t *ClientSignalsTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	for k, v := range t.headers {
		req.Header.Set(k, v)
	}

	if ua := req.Header.Get("User-Agent"); ua != "" {
		req.Header.Set("User-Agent", ua+" "+t.uaSuffix)
	} else {
		req.Header.Set("User-Agent", t.uaSuffix)
	}

	return t.InnerTransport.RoundTrip(req)
}
