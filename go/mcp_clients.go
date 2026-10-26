package clientsignals

// mcpField is the request input an MCP client rule is evaluated against.
type mcpField int

const (
	// mcpVendorClient is the X-Anthropic-Client header.
	mcpVendorClient mcpField = iota
	// mcpUserAgent is the User-Agent header.
	mcpUserAgent
	// mcpClientName is the caller-supplied MCP clientInfo.name.
	mcpClientName
)

// mcpMatchKind describes how a normalized input is compared to a rule value.
type mcpMatchKind int

const (
	// mcpExact means the normalized input must equal the value.
	mcpExact mcpMatchKind = iota
	// mcpPrefix means the normalized input must start with the value. Only
	// used for separator-terminated families such as "grok-shell-".
	mcpPrefix
	// mcpToken means the normalized input must equal the value, or start with
	// it followed by one of '/', ' ', '(' or ';'.
	mcpToken
)

// mcpClientRule is one recognized MCP client identifier. value and contains
// are stored already normalized (ASCII-lowercased; vendor values also have
// '-', '_' and ' ' removed).
//
// See docs/mcp-clients.md for the provenance and confidence of each entry,
// the deliberate exclusions, and the checklist for adding a new one before
// editing this table. Keep it aligned with ../spec/mcp-clients.json: rows are
// ordered and the first match wins within a precedence tier.
//
// Never add rules for X-OpenAI-Session, X-OpenAI-Subject, openai/* _meta,
// auth headers, or anything secret-shaped.
var mcpClientRules = []mcpClientRule{
	{client: "claude-code", field: mcpVendorClient, kind: mcpExact, value: "claudecode"},
	{client: "claude-ai", field: mcpVendorClient, kind: mcpExact, value: "claudeai"},
	{client: "claude-ai", field: mcpVendorClient, kind: mcpExact, value: "claudeartifacts"},
	{client: "claude-ai", field: mcpVendorClient, kind: mcpExact, value: "cowork"},

	{client: "claude-code", field: mcpUserAgent, kind: mcpToken, value: "claude-code"},
	{client: "claude-ai", field: mcpUserAgent, kind: mcpToken, value: "claude-user"},
	{client: "codex", field: mcpUserAgent, kind: mcpToken, value: "codex-mcp-client"},
	{client: "chatgpt", field: mcpUserAgent, kind: mcpToken, value: "openai-mcp", contains: "(chatgpt)"},
	{client: "codex", field: mcpUserAgent, kind: mcpToken, value: "openai-mcp", contains: "(codex)"},
	{client: "openai-api", field: mcpUserAgent, kind: mcpToken, value: "openai-mcp", contains: "(responses api)"},
	{client: "openai-api", field: mcpUserAgent, kind: mcpToken, value: "openai-mcp", contains: "(agent builder)"},
	{client: "openai", field: mcpUserAgent, kind: mcpToken, value: "openai-mcp", weak: true},
	{client: "vscode", field: mcpUserAgent, kind: mcpToken, value: "visual studio code"},
	{client: "cursor", field: mcpUserAgent, kind: mcpToken, value: "cursor"},
	{client: "copilot", field: mcpUserAgent, kind: mcpToken, value: "copilot"},
	{client: "copilot", field: mcpUserAgent, kind: mcpToken, value: "githubcopilot"},
	{client: "zed", field: mcpUserAgent, kind: mcpToken, value: "zed"},
	{client: "goose", field: mcpUserAgent, kind: mcpToken, value: "goose"},
	{client: "grok", field: mcpUserAgent, kind: mcpToken, value: "grok-cli"},

	{client: "claude-code", field: mcpClientName, kind: mcpExact, value: "claude-code"},
	{client: "claude-ai", field: mcpClientName, kind: mcpExact, value: "claude-ai"},
	{client: "claude-ai", field: mcpClientName, kind: mcpExact, value: "anthropic/claudeai", weak: true},
	{client: "claude-ai", field: mcpClientName, kind: mcpExact, value: "anthropic", weak: true},
	{client: "anthropic-api", field: mcpClientName, kind: mcpExact, value: "anthropic/api"},
	{client: "codex", field: mcpClientName, kind: mcpExact, value: "codex-mcp-client"},
	{client: "openai-api", field: mcpClientName, kind: mcpExact, value: "openai-mcp (responses api)"},
	{client: "openai", field: mcpClientName, kind: mcpExact, value: "openai-mcp", weak: true},
	{client: "vscode", field: mcpClientName, kind: mcpExact, value: "visual studio code"},
	{client: "copilot", field: mcpClientName, kind: mcpExact, value: "github-copilot-developer"},
	{client: "cursor", field: mcpClientName, kind: mcpExact, value: "cursor-vscode"},
	{client: "cursor", field: mcpClientName, kind: mcpExact, value: "cursor"},
	{client: "zed", field: mcpClientName, kind: mcpExact, value: "zed"},
	{client: "jetbrains-ai", field: mcpClientName, kind: mcpExact, value: "jetbrains-ai-assistant-client"},
	{client: "junie", field: mcpClientName, kind: mcpExact, value: "junie-client"},
	{client: "gemini-cli", field: mcpClientName, kind: mcpExact, value: "gemini-cli-mcp-client"},
	{client: "goose", field: mcpClientName, kind: mcpExact, value: "goose-cli"},
	{client: "goose", field: mcpClientName, kind: mcpExact, value: "goose-desktop"},
	{client: "opencode", field: mcpClientName, kind: mcpExact, value: "opencode"},
	{client: "cline", field: mcpClientName, kind: mcpExact, value: "cline"},
	{client: "cline", field: mcpClientName, kind: mcpExact, value: "@cline/core"},
	{client: "roo-code", field: mcpClientName, kind: mcpExact, value: "roo code"},
	{client: "kilo-code", field: mcpClientName, kind: mcpExact, value: "kilo"},
	{client: "kilo-code", field: mcpClientName, kind: mcpExact, value: "kilo code"},
	{client: "continue", field: mcpClientName, kind: mcpExact, value: "continue-client"},
	{client: "continue", field: mcpClientName, kind: mcpExact, value: "continue-cli-client"},
	{client: "kiro", field: mcpClientName, kind: mcpExact, value: "q dev cli"},
	{client: "augment", field: mcpClientName, kind: mcpExact, value: "augment-mcp-client"},
	{client: "amp", field: mcpClientName, kind: mcpExact, value: "amp-mcp-client"},
	{client: "warp", field: mcpClientName, kind: mcpPrefix, value: "dev.warp."},
	{client: "warp", field: mcpClientName, kind: mcpExact, value: "warp"},
	{client: "librechat", field: mcpClientName, kind: mcpExact, value: "@librechat/api-client"},
	{client: "grok", field: mcpClientName, kind: mcpPrefix, value: "grok-shell-"},
	{client: "pi", field: mcpClientName, kind: mcpExact, value: "pi"},
	{client: "openclaw", field: mcpClientName, kind: mcpPrefix, value: "openclaw-"},
	{client: "hermes", field: mcpClientName, kind: mcpExact, value: "hermes-agent"},
}

type mcpClientRule struct {
	client   string
	field    mcpField
	kind     mcpMatchKind
	value    string
	contains string // optional normalized substring that must also appear
	weak     bool   // weak rules only apply after every non-weak tier
}
