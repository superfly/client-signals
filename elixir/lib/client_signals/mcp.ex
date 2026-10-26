defmodule ClientSignals.MCP do
  @moduledoc """
  Opt-in, inferred MCP client identity for requests on routes a service
  declares as MCP routes.

  Real MCP clients never send `Fly-Client-*` headers, but they do identify
  themselves through `clientInfo.name`, `User-Agent`, and (for the claude.ai
  relay) `X-Anthropic-Client`. These values are matched against the shared
  rule table in `spec/mcp-clients.json` and reduced to a bounded client label,
  `"other"`, or `""`. Raw values are never returned.

  Only apply this to MCP routes: `Claude-User` is also the User-Agent of
  Claude Code's WebFetch, so it would mislabel ordinary REST traffic. The
  result is inferred and caller-controlled; never use it for gating.
  """

  alias ClientSignals.Request

  @operator_mcp "mcp"

  @source_vendor_header "vendor_header"
  @source_user_agent "user_agent"
  @source_client_info "client_info"
  @source_none "none"

  @client_other "other"

  @max_input_bytes 256
  @ascii_whitespace ~c" \t\n\r\f\v"
  @token_separators ~c"/ (;"
  @mcp_remote_suffix " (via mcp-remote"
  @client_info_meta_key "io.modelcontextprotocol/clientInfo"

  # Keep aligned with ../spec/mcp-clients.json. Rows are ordered; the first
  # match within a precedence tier wins.
  @rules [
    %{
      "client" => "claude-code",
      "field" => "vendorClient",
      "kind" => "exact",
      "value" => "claudecode"
    },
    %{
      "client" => "claude-ai",
      "field" => "vendorClient",
      "kind" => "exact",
      "value" => "claudeai"
    },
    %{
      "client" => "claude-ai",
      "field" => "vendorClient",
      "kind" => "exact",
      "value" => "claudeartifacts"
    },
    %{"client" => "claude-ai", "field" => "vendorClient", "kind" => "exact", "value" => "cowork"},
    %{
      "client" => "claude-code",
      "field" => "userAgent",
      "kind" => "token",
      "value" => "claude-code"
    },
    %{
      "client" => "claude-ai",
      "field" => "userAgent",
      "kind" => "token",
      "value" => "claude-user"
    },
    %{
      "client" => "codex",
      "field" => "userAgent",
      "kind" => "token",
      "value" => "codex-mcp-client"
    },
    %{
      "client" => "chatgpt",
      "field" => "userAgent",
      "kind" => "token",
      "value" => "openai-mcp",
      "contains" => "(chatgpt)"
    },
    %{
      "client" => "codex",
      "field" => "userAgent",
      "kind" => "token",
      "value" => "openai-mcp",
      "contains" => "(codex)"
    },
    %{
      "client" => "openai-api",
      "field" => "userAgent",
      "kind" => "token",
      "value" => "openai-mcp",
      "contains" => "(responses api)"
    },
    %{
      "client" => "openai-api",
      "field" => "userAgent",
      "kind" => "token",
      "value" => "openai-mcp",
      "contains" => "(agent builder)"
    },
    %{
      "client" => "openai",
      "field" => "userAgent",
      "kind" => "token",
      "value" => "openai-mcp",
      "weak" => true
    },
    %{
      "client" => "vscode",
      "field" => "userAgent",
      "kind" => "token",
      "value" => "visual studio code"
    },
    %{"client" => "cursor", "field" => "userAgent", "kind" => "token", "value" => "cursor"},
    %{"client" => "copilot", "field" => "userAgent", "kind" => "token", "value" => "copilot"},
    %{
      "client" => "copilot",
      "field" => "userAgent",
      "kind" => "token",
      "value" => "githubcopilot"
    },
    %{"client" => "zed", "field" => "userAgent", "kind" => "token", "value" => "zed"},
    %{"client" => "goose", "field" => "userAgent", "kind" => "token", "value" => "goose"},
    %{"client" => "grok", "field" => "userAgent", "kind" => "token", "value" => "grok-cli"},
    %{
      "client" => "claude-code",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "claude-code"
    },
    %{
      "client" => "claude-ai",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "claude-ai"
    },
    %{
      "client" => "claude-ai",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "anthropic/claudeai",
      "weak" => true
    },
    %{
      "client" => "claude-ai",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "anthropic",
      "weak" => true
    },
    %{
      "client" => "anthropic-api",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "anthropic/api"
    },
    %{
      "client" => "codex",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "codex-mcp-client"
    },
    %{
      "client" => "openai-api",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "openai-mcp (responses api)"
    },
    %{
      "client" => "openai",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "openai-mcp",
      "weak" => true
    },
    %{
      "client" => "vscode",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "visual studio code"
    },
    %{
      "client" => "copilot",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "github-copilot-developer"
    },
    %{
      "client" => "cursor",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "cursor-vscode"
    },
    %{"client" => "cursor", "field" => "clientName", "kind" => "exact", "value" => "cursor"},
    %{"client" => "zed", "field" => "clientName", "kind" => "exact", "value" => "zed"},
    %{
      "client" => "jetbrains-ai",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "jetbrains-ai-assistant-client"
    },
    %{"client" => "junie", "field" => "clientName", "kind" => "exact", "value" => "junie-client"},
    %{
      "client" => "gemini-cli",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "gemini-cli-mcp-client"
    },
    %{"client" => "goose", "field" => "clientName", "kind" => "exact", "value" => "goose-cli"},
    %{
      "client" => "goose",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "goose-desktop"
    },
    %{"client" => "opencode", "field" => "clientName", "kind" => "exact", "value" => "opencode"},
    %{"client" => "cline", "field" => "clientName", "kind" => "exact", "value" => "cline"},
    %{"client" => "cline", "field" => "clientName", "kind" => "exact", "value" => "@cline/core"},
    %{"client" => "roo-code", "field" => "clientName", "kind" => "exact", "value" => "roo code"},
    %{"client" => "kilo-code", "field" => "clientName", "kind" => "exact", "value" => "kilo"},
    %{
      "client" => "kilo-code",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "kilo code"
    },
    %{
      "client" => "continue",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "continue-client"
    },
    %{
      "client" => "continue",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "continue-cli-client"
    },
    %{"client" => "kiro", "field" => "clientName", "kind" => "exact", "value" => "q dev cli"},
    %{
      "client" => "augment",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "augment-mcp-client"
    },
    %{"client" => "amp", "field" => "clientName", "kind" => "exact", "value" => "amp-mcp-client"},
    %{"client" => "warp", "field" => "clientName", "kind" => "prefix", "value" => "dev.warp."},
    %{"client" => "warp", "field" => "clientName", "kind" => "exact", "value" => "warp"},
    %{
      "client" => "librechat",
      "field" => "clientName",
      "kind" => "exact",
      "value" => "@librechat/api-client"
    },
    %{"client" => "grok", "field" => "clientName", "kind" => "prefix", "value" => "grok-shell-"},
    %{"client" => "pi", "field" => "clientName", "kind" => "exact", "value" => "pi"},
    %{
      "client" => "openclaw",
      "field" => "clientName",
      "kind" => "prefix",
      "value" => "openclaw-"
    },
    %{"client" => "hermes", "field" => "clientName", "kind" => "exact", "value" => "hermes-agent"}
  ]

  @labels @rules |> Enum.map(& &1["client"]) |> Enum.uniq()

  @sources %{
    "vendorClient" => @source_vendor_header,
    "userAgent" => @source_user_agent,
    "clientName" => @source_client_info
  }

  # Non-weak rules by field (vendor header, then User-Agent, then clientInfo),
  # then weak User-Agent and weak clientInfo rules.
  @tiers [
    {"vendorClient", false},
    {"userAgent", false},
    {"clientName", false},
    {"userAgent", true},
    {"clientName", true}
  ]

  @doc "Returns the MCP client rule table, mirroring `spec/mcp-clients.json`."
  def rules, do: @rules

  @doc "Returns the bounded MCP client labels, in rule order."
  def labels, do: @labels

  @doc """
  Identifies the MCP client from the `User-Agent` header, the
  `X-Anthropic-Client` header, and the caller-supplied `clientInfo.name`.

  Returns `%{client: client, source: source}`. `client` is a bounded label,
  `"other"` for a `clientInfo.name` that matched no rule, or `""` when no
  client is identified. `source` is `vendor_header`, `user_agent`,
  `client_info`, or `none`. An unrecognized User-Agent or vendor header alone
  never produces a client. `nil` or non-binary inputs are treated as absent.
  """
  def classify_client(user_agent, vendor_client, client_name) do
    inputs = %{
      "vendorClient" => normalize(vendor_client, :vendor_client),
      "userAgent" => normalize(user_agent, :user_agent),
      "clientName" => normalize(client_name, :client_name)
    }

    Enum.find_value(@tiers, fn {field, weak?} -> match_tier(field, weak?, inputs[field]) end) ||
      if inputs["clientName"] do
        %{client: @client_other, source: @source_client_info}
      else
        %{client: "", source: @source_none}
      end
  end

  @doc """
  Classifies a request on an MCP route into bounded `operator` and `agent`
  labels.

  A valid `Fly-Client-Interactive` sentinel wins and the result is exactly
  `ClientSignals.Request.classify/3`. Otherwise an identified MCP client yields
  operator `mcp` with the client label as the agent, and anything else stays
  `uninstrumented` / `none`.
  """
  def classify_request(interactive, agent, ci, user_agent, vendor_client, client_name) do
    case Request.classify(interactive, agent, ci) do
      %{operator: "uninstrumented"} = classification ->
        case classify_client(user_agent, vendor_client, client_name) do
          %{client: ""} -> classification
          %{client: client} -> %{operator: @operator_mcp, agent: client}
        end

      classification ->
        classification
    end
  end

  @doc """
  Returns the caller-supplied `clientInfo.name` from decoded JSON-RPC request
  params, or `nil`.

  Accepts either the params map or the full request map
  (`%{"method" => ..., "params" => ...}`, e.g. `conn.body_params`).
  `params["_meta"]["io.modelcontextprotocol/clientInfo"]["name"]` is preferred;
  otherwise `params["clientInfo"]["name"]` is used, for a full request only
  when its method is `initialize`. Batches, structs (such as
  `%Plug.Conn.Unfetched{}`), and anything else return `nil`.
  """
  def client_name(%_{}), do: nil

  def client_name(%{"method" => method, "params" => params}) when is_map(params) do
    meta_client_name(params) ||
      if(method == "initialize", do: client_info_name(params))
  end

  def client_name(%{"method" => _method}), do: nil

  def client_name(params) when is_map(params) do
    meta_client_name(params) || client_info_name(params)
  end

  def client_name(_params), do: nil

  defp meta_client_name(%{"_meta" => %{@client_info_meta_key => client_info}}),
    do: name(client_info)

  defp meta_client_name(_params), do: nil

  defp client_info_name(%{"clientInfo" => client_info}), do: name(client_info)
  defp client_info_name(_params), do: nil

  defp name(%_{}), do: nil
  defp name(%{"name" => name}) when is_binary(name), do: name
  defp name(_client_info), do: nil

  defp match_tier(_field, _weak?, nil), do: nil

  defp match_tier(field, weak?, input) do
    Enum.find_value(@rules, fn rule ->
      if rule["field"] == field and Map.get(rule, "weak", false) == weak? and
           matches?(rule, input) do
        %{client: rule["client"], source: @sources[field]}
      end
    end)
  end

  defp matches?(rule, input) do
    kind_matches?(rule["kind"], rule["value"], input) and
      (is_nil(rule["contains"]) or :binary.match(input, rule["contains"]) != :nomatch)
  end

  defp kind_matches?("exact", value, input), do: input == value

  defp kind_matches?("prefix", value, input), do: starts_with?(input, value)

  defp kind_matches?("token", value, input) do
    input == value or
      (starts_with?(input, value) and :binary.at(input, byte_size(value)) in @token_separators)
  end

  defp starts_with?(input, value) do
    byte_size(input) >= byte_size(value) and binary_part(input, 0, byte_size(value)) == value
  end

  # Byte-oriented so Go and Elixir agree: trim ASCII whitespace, keep the first
  # 256 bytes, and lowercase A-Z only.
  defp normalize(value, field) when is_binary(value) do
    value = trim_ascii(value)

    value =
      value
      |> binary_part(0, min(byte_size(value), @max_input_bytes))
      |> downcase_ascii()
      |> normalize_field(field)

    if value == "", do: nil, else: value
  end

  defp normalize(_value, _field), do: nil

  # mcp-remote appends " (via mcp-remote <version>)" to the downstream name.
  defp normalize_field(value, :client_name) do
    case :binary.match(value, @mcp_remote_suffix) do
      {index, _length} -> value |> binary_part(0, index) |> trim_ascii()
      :nomatch -> value
    end
  end

  defp normalize_field(value, :vendor_client), do: String.replace(value, ["-", "_", " "], "")
  defp normalize_field(value, _field), do: value

  defp trim_ascii(value), do: value |> trim_leading_ascii() |> trim_trailing_ascii()

  defp trim_leading_ascii(<<char, rest::binary>>) when char in @ascii_whitespace,
    do: trim_leading_ascii(rest)

  defp trim_leading_ascii(value), do: value

  defp trim_trailing_ascii(""), do: ""

  defp trim_trailing_ascii(value) do
    if :binary.last(value) in @ascii_whitespace do
      value |> binary_part(0, byte_size(value) - 1) |> trim_trailing_ascii()
    else
      value
    end
  end

  defp downcase_ascii(value) do
    for <<char <- value>>, into: "", do: <<if(char in ?A..?Z, do: char + 32, else: char)>>
  end
end
