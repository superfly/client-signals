defmodule ClientSignals.Request do
  @moduledoc """
  Bounded server-side classification and route helpers for incoming
  client-signal headers.

  The returned operator and agent values are safe to use as metric labels.
  """

  @operator_ci "ci"
  @operator_agent "agent"
  @operator_interactive "interactive"
  @operator_automated_unattributed "automated_unattributed"
  @operator_uninstrumented "uninstrumented"

  @agent_none "none"
  @agent_other "other"

  @doc """
  Classifies incoming header values into bounded `operator` and `agent` labels.

  `interactive` is the instrumentation sentinel. Parent is deliberately not
  considered because parent-process lookup is not reliable enough for request
  classification. CI takes precedence over agent, which takes precedence over
  interactive. The agent label is preserved for CI requests.
  """
  def classify(interactive, agent, ci) do
    case parse_bool(interactive) do
      {:ok, interactive?} ->
        agent = normalize_agent(agent)

        operator =
          cond do
            parse_true?(ci) -> @operator_ci
            agent != @agent_none -> @operator_agent
            interactive? -> @operator_interactive
            true -> @operator_automated_unattributed
          end

        %{operator: operator, agent: agent}

      :error ->
        %{operator: @operator_uninstrumented, agent: @agent_none}
    end
  end

  @doc """
  Returns a bounded route metric label and whether the request is tracked.

  A matched route template is preferred. For an unmatched request, the raw
  request path is used only for prefix selection and is never returned.
  """
  def tracked_route(method, route_template, request_path, prefixes) do
    method =
      case method |> to_string() |> String.trim() |> String.upcase() do
        "" -> "UNKNOWN"
        method -> method
      end

    cond do
      present?(route_template) and matches_prefix?(route_template, prefixes) ->
        {method <> " " <> route_template, true}

      present?(route_template) ->
        {"", false}

      matches_prefix?(request_path, prefixes) ->
        {method <> " unmatched", true}

      true ->
        {"", false}
    end
  end

  defp normalize_agent(agent) when is_binary(agent) do
    case ClientSignals.sanitize_invoked_by(agent) do
      {agent, true} ->
        if agent in ClientSignals.known_agents(), do: agent, else: @agent_other

      {"", false} ->
        @agent_none
    end
  end

  defp normalize_agent(_agent), do: @agent_none

  defp parse_true?(value), do: parse_bool(value) == {:ok, true}

  defp parse_bool(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      value when value in ~w(1 t true) -> {:ok, true}
      value when value in ~w(0 f false) -> {:ok, false}
      _value -> :error
    end
  end

  defp parse_bool(_value), do: :error

  defp matches_prefix?(path, prefixes) when is_binary(path) do
    Enum.any?(prefixes, fn prefix ->
      prefix = String.trim_trailing(prefix, "/")

      cond do
        prefix in ["", "/"] -> String.starts_with?(path, "/")
        path == prefix -> true
        true -> String.starts_with?(path, prefix <> "/")
      end
    end)
  end

  defp matches_prefix?(_path, _prefixes), do: false

  defp present?(value), do: is_binary(value) and value != ""
end
