package clientsignals

import (
	"net/http"
	"strings"
)

const (
	// RequestOperatorMCP identifies uninstrumented requests to a declared MCP
	// route whose MCP client was inferred from User-Agent, X-Anthropic-Client,
	// or clientInfo.name. Only ClassifyMCPRequest produces it.
	RequestOperatorMCP = "mcp"

	// MCPSourceVendorHeader means the MCP client came from X-Anthropic-Client.
	MCPSourceVendorHeader = "vendor_header"
	// MCPSourceUserAgent means the MCP client came from User-Agent.
	MCPSourceUserAgent = "user_agent"
	// MCPSourceClientInfo means the MCP client came from clientInfo.name.
	MCPSourceClientInfo = "client_info"
	// MCPSourceNone means no MCP client was identified.
	MCPSourceNone = "none"

	// mcpMetaClientInfoKey is the _meta key carrying clientInfo on every
	// request from protocol 2026-07-28.
	mcpMetaClientInfoKey = "io.modelcontextprotocol/clientInfo"

	maxMCPInputLen   = 256
	mcpRemoteSuffix  = " (via mcp-remote"
	asciiWhitespace  = " \t\n\r\f\v"
	mcpVendorRemoved = "-_ "
)

// MCPClient is the bounded MCP client inferred for a request. Client is a
// label from the MCP client table, RequestAgentOther, or "" when no client was
// identified. Source is one of the MCPSource* constants. Both are safe to use
// as metric labels or span attributes; raw inputs are never returned.
type MCPClient struct {
	Client string
	Source string
}

// mcpTiers is the single-pass precedence: non-weak vendor header, User-Agent,
// and clientInfo rules, then weak User-Agent and clientInfo rules.
var mcpTiers = []struct {
	field mcpField
	weak  bool
}{
	{mcpVendorClient, false},
	{mcpUserAgent, false},
	{mcpClientName, false},
	{mcpUserAgent, true},
	{mcpClientName, true},
}

// ClassifyMCPClient infers the MCP client from the X-Anthropic-Client and
// User-Agent headers and the caller-supplied clientInfo.name. Pass "" for
// clientName when the request carries no clientInfo.
//
// An unrecognized User-Agent or vendor header alone never produces a client,
// which keeps scanners, browsers, and curl hitting an MCP route out of the
// mcp operator. A non-empty clientName that matches no rule produces
// RequestAgentOther, because only real MCP clients send clientInfo.
//
// Only call this for routes the service declares as MCP routes: some matched
// User-Agents (such as Claude-User) are also sent by non-MCP fetches.
func ClassifyMCPClient(header http.Header, clientName string) MCPClient {
	inputs := [...]string{
		mcpVendorClient: normalizeMCPInput(header.Get("X-Anthropic-Client"), mcpVendorClient),
		mcpUserAgent:    normalizeMCPInput(header.Get("User-Agent"), mcpUserAgent),
		mcpClientName:   normalizeMCPInput(clientName, mcpClientName),
	}

	for _, tier := range mcpTiers {
		input := inputs[tier.field]
		if input == "" {
			continue
		}
		for _, rule := range mcpClientRules {
			if rule.field == tier.field && rule.weak == tier.weak && rule.matches(input) {
				return MCPClient{Client: rule.client, Source: mcpSource(tier.field)}
			}
		}
	}

	if inputs[mcpClientName] != "" {
		return MCPClient{Client: RequestAgentOther, Source: MCPSourceClientInfo}
	}

	return MCPClient{Client: "", Source: MCPSourceNone}
}

// ClassifyMCPRequest returns bounded metric-label values for a request to a
// declared MCP route. A valid Fly-Client-Interactive self-report wins and is
// classified exactly as ClassifyRequestHeaders does. Otherwise an identified
// MCP client yields operator RequestOperatorMCP with the client label as the
// agent, and anything else is uninstrumented.
func ClassifyMCPRequest(header http.Header, clientName string) RequestClassification {
	if _, ok := parseRequestBool(header.Get(DefaultHeaderPrefix + "-Client-Interactive")); ok {
		return ClassifyRequestHeaders(header)
	}

	if client := ClassifyMCPClient(header, clientName); client.Client != "" {
		return RequestClassification{Operator: RequestOperatorMCP, Agent: client.Client}
	}

	return RequestClassification{
		Operator: RequestOperatorUninstrumented,
		Agent:    RequestAgentNone,
	}
}

// MCPClientNameFromMeta returns meta["io.modelcontextprotocol/clientInfo"]
// ["name"] from a decoded JSON-RPC params._meta object, or "" when it is
// missing or not a string. The result is caller-controlled and must only be
// passed to ClassifyMCPClient or ClassifyMCPRequest, never used as a label.
//
// With modelcontextprotocol/go-sdk, pass params.Meta directly (mcp.Meta is a
// map[string]any). With mark3labs/mcp-go, Params.Meta is a *mcp.Meta that may
// be nil, and the key lives in its AdditionalFields:
//
//	if m := req.Params.Meta; m != nil {
//		name = clientsignals.MCPClientNameFromMeta(m.AdditionalFields)
//	}
func MCPClientNameFromMeta(meta map[string]any) string {
	clientInfo, ok := meta[mcpMetaClientInfoKey].(map[string]any)
	if !ok {
		return ""
	}
	name, _ := clientInfo["name"].(string)

	return name
}

func (r mcpClientRule) matches(input string) bool {
	var ok bool
	switch r.kind {
	case mcpExact:
		ok = input == r.value
	case mcpPrefix:
		ok = strings.HasPrefix(input, r.value)
	case mcpToken:
		ok = input == r.value ||
			(strings.HasPrefix(input, r.value) && isMCPTokenBoundary(input[len(r.value)]))
	}
	if ok && r.contains != "" {
		ok = strings.Contains(input, r.contains)
	}

	return ok
}

func isMCPTokenBoundary(b byte) bool {
	return b == '/' || b == ' ' || b == '(' || b == ';'
}

// normalizeMCPInput applies the byte-oriented normalization shared by every
// implementation: trim ASCII whitespace, truncate to 256 bytes, and lowercase
// ASCII A-Z only (strings.ToLower would fold non-ASCII runes such as the
// Kelvin sign into ASCII). An empty result means the input is absent.
func normalizeMCPInput(raw string, field mcpField) string {
	value := strings.Trim(raw, asciiWhitespace)
	if len(value) > maxMCPInputLen {
		value = value[:maxMCPInputLen]
	}
	value = lowerASCII(value)

	switch field {
	case mcpClientName:
		// mcp-remote appends " (via mcp-remote <version>)" to the downstream
		// client's name.
		if i := strings.Index(value, mcpRemoteSuffix); i >= 0 {
			value = strings.Trim(value[:i], asciiWhitespace)
		}
	case mcpVendorClient:
		// ClaudeCode, claude-code, and claude_code all become claudecode.
		value = removeBytes(value, mcpVendorRemoved)
	}

	return value
}

// removeBytes drops every byte of s found in cut. It works on bytes rather
// than runes so truncated or invalid UTF-8 is left untouched.
func removeBytes(s, cut string) string {
	b := make([]byte, 0, len(s))
	for i := range len(s) {
		if strings.IndexByte(cut, s[i]) < 0 {
			b = append(b, s[i])
		}
	}

	return string(b)
}

func lowerASCII(s string) string {
	b := []byte(s)
	for i, c := range b {
		if 'A' <= c && c <= 'Z' {
			b[i] = c + ('a' - 'A')
		}
	}

	return string(b)
}

func mcpSource(field mcpField) string {
	switch field {
	case mcpVendorClient:
		return MCPSourceVendorHeader
	case mcpUserAgent:
		return MCPSourceUserAgent
	case mcpClientName:
		return MCPSourceClientInfo
	default:
		return MCPSourceNone
	}
}
