if Code.ensure_loaded?(Plug.Conn) and Code.ensure_loaded?(OpenTelemetry.Tracer) do
  defmodule ClientSignals.Plug do
    @moduledoc """
    Reads the coarse, self-reported `Fly-Client-*` headers (as produced by
    `ClientSignals.headers_for/2`) off an incoming request and attaches
    them to the current request's OTel span as `fly.client.*` attributes.

    This gives services a rough human-vs-agent traffic estimate for
    capacity planning and product decisions. These values are self-reported
    by the caller and must never be used for gating, enforcement, or any
    per-request trust decision.

    This module is only defined when both `:plug` and `:opentelemetry_api`
    are loaded; both are optional dependencies of `:client_signals`.
    """

    import Plug.Conn
    require OpenTelemetry.Tracer, as: Tracer

    @behaviour Plug

    @interactive_header "fly-client-interactive"
    @parent_header "fly-client-parent"
    @agent_header "fly-client-agent"
    @agent_source_header "fly-client-agent-source"
    @ci_header "fly-client-ci"

    # Headers are caller-controlled; bound how much of them we keep so a
    # malicious or misbehaving client can't bloat span payloads.
    @max_value_length 256

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, _opts) do
      attrs = client_signal_attributes(conn)

      if attrs != [] do
        Tracer.set_attributes(attrs)
      end

      conn
    end

    @doc false
    def client_signal_attributes(conn) do
      []
      |> put_bool_attr(conn, @interactive_header, "fly.client.interactive")
      |> put_string_attr(conn, @parent_header, "fly.client.parent")
      |> put_string_attr(conn, @agent_header, "fly.client.agent")
      |> put_string_attr(conn, @agent_source_header, "fly.client.agent_source")
      |> put_bool_attr(conn, @ci_header, "fly.client.ci")
    end

    defp put_string_attr(attrs, conn, header, key) do
      case get_req_header(conn, header) do
        [value | _] ->
          case String.trim(value) do
            "" -> attrs
            trimmed -> [{key, String.slice(trimmed, 0, @max_value_length)} | attrs]
          end

        _ ->
          attrs
      end
    end

    defp put_bool_attr(attrs, conn, header, key) do
      case get_req_header(conn, header) do
        [value | _] ->
          case parse_bool(value) do
            {:ok, bool} -> [{key, bool} | attrs]
            :error -> attrs
          end

        _ ->
          attrs
      end
    end

    defp parse_bool(value) do
      case value |> String.trim() |> String.downcase() do
        v when v in ~w(1 t true) -> {:ok, true}
        v when v in ~w(0 f false) -> {:ok, false}
        _ -> :error
      end
    end
  end
end
