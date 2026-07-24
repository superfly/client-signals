defmodule ClientSignals do
  @moduledoc """
  Privacy-safe client signals for CLI HTTP traffic.
  """

  @default_header_prefix "Fly"
  @max_invoked_by_len 64

  @known_markers [
    %{"agent" => "claude-code", "env" => "CLAUDECODE", "kind" => "exactValue", "values" => ["1"]},
    %{"agent" => "claude-code", "env" => "CLAUDE_CODE_ENTRYPOINT", "kind" => "presence"},
    %{"agent" => "pi", "env" => "PI_CODING_AGENT", "kind" => "exactValue", "values" => ["true"]},
    %{
      "agent" => "openclaw",
      "env" => "OPENCLAW_SHELL",
      "kind" => "exactValue",
      "values" => ["exec"]
    },
    %{"agent" => "openclaw", "env" => "OPENCLAW_CLI", "kind" => "exactValue", "values" => ["1"]},
    %{"agent" => "goose", "env" => "GOOSE_TERMINAL", "kind" => "exactValue", "values" => ["1"]},
    %{"agent" => "hermes", "env" => "HERMES_SESSION_ID", "kind" => "presence"},
    %{"agent" => "codex", "env" => "CODEX_SANDBOX", "kind" => "presence"},
    %{"agent" => "codex", "env" => "CODEX_THREAD_ID", "kind" => "presence"},
    %{"agent" => "cursor", "env" => "CURSOR_TRACE_ID", "kind" => "presence"},
    %{"agent" => "cursor", "env" => "CURSOR_AGENT", "kind" => "presence"},
    %{"agent" => "gemini-cli", "env" => "GEMINI_CLI", "kind" => "presence"},
    %{"agent" => "kiro", "env" => "TERM_PROGRAM", "kind" => "exactValue", "values" => ["kiro"]},
    %{"agent" => "antigravity", "env" => "ANTIGRAVITY_AGENT", "kind" => "presence"},
    %{"agent" => "augment", "env" => "AUGMENT_AGENT", "kind" => "presence"},
    %{"agent" => "replit", "env" => "REPL_ID", "kind" => "presence"},
    %{"agent" => "opencode", "env" => "OPENCODE", "kind" => "presence"},
    %{"agent" => "opencode", "env" => "OPENCODE_CALLER", "kind" => "presence"},
    %{"agent" => "opencode", "env" => "OPENCODE_CLIENT", "kind" => "presence"},
    %{"agent" => "copilot", "env" => "COPILOT_MODEL", "kind" => "presence"},
    %{"agent" => "copilot", "env" => "COPILOT_ALLOW_ALL", "kind" => "presence"},
    %{
      "agent" => "kilo-code",
      "env" => "KILO_PLATFORM",
      "kind" => "exactValue",
      "values" => ["vscode"]
    }
  ]
  @known_agents @known_markers
                |> Enum.map(& &1["agent"])
                |> Enum.uniq()

  defstruct interactive: false, parent: "other", agent: "", agent_source: "", ci: false

  def default_header_prefix, do: @default_header_prefix
  def known_markers, do: @known_markers
  def known_agents, do: @known_agents

  def detect do
    {agent, source} = detect_agent()

    %__MODULE__{
      interactive: interactive?(),
      parent: parent_bucket(),
      agent: agent,
      agent_source: source,
      ci: ci?()
    }
  end

  def detect_once do
    case :persistent_term.get({__MODULE__, :signals}, :unset) do
      :unset ->
        signals = detect()
        :persistent_term.put({__MODULE__, :signals}, signals)
        signals

      signals ->
        signals
    end
  end

  def reset_cached_for_test do
    :persistent_term.erase({__MODULE__, :signals})
    :ok
  end

  def headers_for(signals, prefix \\ @default_header_prefix) do
    headers = %{
      "#{prefix}-Client-Interactive" => field(signals, :interactive) |> to_string(),
      "#{prefix}-Client-Parent" => field(signals, :parent)
    }

    headers =
      if field(signals, :agent) != "" do
        headers
        |> Map.put("#{prefix}-Client-Agent", field(signals, :agent))
        |> Map.put("#{prefix}-Client-Agent-Source", field(signals, :agent_source))
      else
        headers
      end

    if field(signals, :ci) do
      Map.put(headers, "#{prefix}-Client-CI", "true")
    else
      headers
    end
  end

  def apply_headers(headers, signals, prefix \\ @default_header_prefix) when is_map(headers) do
    Map.merge(headers, headers_for(signals, prefix))
  end

  def user_agent_suffix(signals) do
    suffix = "interactive=#{field(signals, :interactive)}; parent=#{field(signals, :parent)}"

    suffix =
      if field(signals, :agent) != "" do
        suffix <> "; agent=#{field(signals, :agent)}"
      else
        suffix
      end

    "(" <> suffix <> ")"
  end

  @doc "Returns one process-operator classification: ci > agent > interactive > unknown."
  def operator(signals) do
    cond do
      field(signals, :ci) -> "ci"
      field(signals, :agent) != "" -> "agent"
      field(signals, :interactive) -> "interactive"
      true -> "unknown"
    end
  end

  def sanitize_invoked_by(value) do
    sanitized = value |> String.trim() |> String.downcase()

    cond do
      sanitized == "" -> {"", false}
      String.length(sanitized) > @max_invoked_by_len -> {"", false}
      Regex.match?(~r/^[a-z0-9][a-z0-9-]{0,63}$/, sanitized) -> {sanitized, true}
      true -> {"", false}
    end
  end

  def classify_parent_name(raw) do
    name =
      raw
      |> Path.basename()
      |> String.downcase()
      |> String.replace_suffix(".exe", "")

    cond do
      name == "node" ->
        "node"

      name in ["python", "python3", "python2"] ->
        "python"

      name in [
        "bash",
        "zsh",
        "fish",
        "sh",
        "dash",
        "ksh",
        "tcsh",
        "csh",
        "cmd",
        "powershell",
        "pwsh"
      ] ->
        "shell"

      true ->
        "other"
    end
  end

  defp detect_agent do
    with value when not is_nil(value) <- System.get_env("FLY_INVOKED_BY"),
         {agent, true} <- sanitize_invoked_by(value) do
      {agent, "env:FLY_INVOKED_BY"}
    else
      _ -> detect_known_marker() || detect_agent_convention()
    end
  end

  defp detect_known_marker do
    Enum.find_value(@known_markers, fn marker ->
      case System.get_env(marker["env"]) do
        nil ->
          nil

        value ->
          cond do
            marker["kind"] == "presence" -> {marker["agent"], "env:#{marker["env"]}"}
            value in marker["values"] -> {marker["agent"], "env:#{marker["env"]}"}
            true -> nil
          end
      end
    end)
  end

  defp detect_agent_convention do
    with value when not is_nil(value) <- System.get_env("AGENT"),
         {agent, true} <- sanitize_invoked_by(value) do
      {agent, "env:AGENT"}
    else
      _ -> {"", ""}
    end
  end

  defp interactive? do
    match?({:ok, _}, :io.columns(:standard_io))
  rescue
    _ -> false
  end

  defp ci? do
    not is_nil(System.get_env("CI")) or not is_nil(System.get_env("GITHUB_ACTIONS"))
  end

  defp parent_bucket do
    self()
    |> Process.info(:dictionary)
    |> elem(1)
    |> Keyword.get(:"$ancestors", [])
    |> List.first()
    |> parent_name()
    |> classify_parent_name()
  end

  defp parent_name(_) do
    ppid = :os.getpid() |> to_string() |> parent_pid()

    case File.read("/proc/#{ppid}/comm") do
      {:ok, name} -> String.trim(name)
      {:error, _} -> ""
    end
  end

  defp parent_pid(pid) do
    case File.read("/proc/#{pid}/stat") do
      {:ok, stat} ->
        stat
        |> String.split()
        |> Enum.at(3, "")

      {:error, _} ->
        ""
    end
  end

  defp field(%__MODULE__{} = signals, name), do: Map.fetch!(signals, name)

  defp field(%{} = signals, :agent_source),
    do: Map.get(signals, "agentSource", Map.get(signals, :agent_source, ""))

  defp field(%{} = signals, name),
    do: Map.get(signals, Atom.to_string(name), Map.get(signals, name))
end
