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

    Routes listed in `:mcp_route_prefixes` are treated as MCP routes: their
    request observations use `ClientSignals.MCP.classify_request/6`, and an
    identified MCP client is attached as the bounded `fly.client.mcp_client`
    and `fly.client.mcp_source` span attributes. The raw User-Agent and
    `clientInfo.name` are never recorded.

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
    @user_agent_header "user-agent"
    @vendor_client_header "x-anthropic-client"

    # Headers are caller-controlled; bound how much of them we keep so a
    # malicious or misbehaving client can't bloat span payloads.
    @max_value_length 256

    @impl true
    def init(opts) do
      service = Keyword.get(opts, :service)
      tracked_route_prefixes = Keyword.get(opts, :tracked_route_prefixes, [])
      configured_request_observer = Keyword.get(opts, :request_observer)
      route_template_provider = Keyword.get(opts, :route_template_provider)
      mcp_route_prefixes = Keyword.get(opts, :mcp_route_prefixes, [])

      metrics_configured? =
        not is_nil(service) or tracked_route_prefixes != [] or
          not is_nil(configured_request_observer) or not is_nil(route_template_provider)

      request_observer =
        cond do
          not metrics_configured? ->
            nil

          not is_nil(configured_request_observer) ->
            configured_request_observer

          Code.ensure_loaded?(ClientSignals.RequestMetrics) ->
            {ClientSignals.RequestMetrics, :observe, []}

          true ->
            nil
        end

      if metrics_configured? and
           (not is_binary(service) or service == "" or tracked_route_prefixes == [] or
              is_nil(route_template_provider)) do
        raise ArgumentError,
              "service, tracked_route_prefixes, and route_template_provider are all required " <>
                "when client-signal request observation is enabled"
      end

      if metrics_configured? and is_nil(request_observer) do
        raise ArgumentError,
              "request_observer is required when :telemetry is unavailable"
      end

      if not is_list(mcp_route_prefixes) or not Enum.all?(mcp_route_prefixes, &is_binary/1) do
        raise ArgumentError, "mcp_route_prefixes must be a list of strings"
      end

      %{
        service: service,
        tracked_route_prefixes: tracked_route_prefixes,
        request_observer: request_observer,
        route_template_provider: route_template_provider,
        mcp_route_prefixes: mcp_route_prefixes
      }
    end

    @impl true
    def call(conn, opts) do
      attrs = client_signal_attributes(conn)

      if attrs != [] do
        Tracer.set_attributes(attrs)
      end

      maybe_register_request_observer(conn, opts)
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

    @doc false
    def mcp_client_attributes(conn) do
      case mcp_client(conn) do
        %{client: ""} ->
          []

        %{client: client, source: source} ->
          [{"fly.client.mcp_client", client}, {"fly.client.mcp_source", source}]
      end
    end

    defp maybe_register_request_observer(conn, %{request_observer: nil, mcp_route_prefixes: []}),
      do: conn

    defp maybe_register_request_observer(conn, opts) do
      register_before_send(conn, fn conn ->
        route_template = route_template(opts.route_template_provider, conn)
        mcp_route? = mcp_route?(conn, route_template, opts.mcp_route_prefixes)

        if mcp_route? do
          attrs = mcp_client_attributes(conn)

          if attrs != [] do
            Tracer.set_attributes(attrs)
          end
        end

        maybe_observe_request(conn, route_template, mcp_route?, opts)
        conn
      end)
    end

    defp maybe_observe_request(_conn, _route_template, _mcp_route?, %{request_observer: nil}),
      do: :ok

    defp maybe_observe_request(conn, route_template, mcp_route?, opts) do
      case ClientSignals.Request.tracked_route(
             conn.method,
             route_template,
             conn.request_path,
             opts.tracked_route_prefixes
           ) do
        {route, true} ->
          labels =
            conn
            |> classify(mcp_route?)
            |> Map.put(:service, opts.service)
            |> Map.put(:route, route)

          notify_request_observer(opts.request_observer, labels)

        {"", false} ->
          :ok
      end
    end

    defp classify(conn, true) do
      ClientSignals.MCP.classify_request(
        first_req_header(conn, @interactive_header),
        first_req_header(conn, @agent_header),
        first_req_header(conn, @ci_header),
        first_req_header(conn, @user_agent_header),
        first_req_header(conn, @vendor_client_header),
        ClientSignals.MCP.client_name(conn.body_params)
      )
    end

    defp classify(conn, false) do
      ClientSignals.Request.classify(
        first_req_header(conn, @interactive_header),
        first_req_header(conn, @agent_header),
        first_req_header(conn, @ci_header)
      )
    end

    defp mcp_client(conn) do
      ClientSignals.MCP.classify_client(
        first_req_header(conn, @user_agent_header),
        first_req_header(conn, @vendor_client_header),
        ClientSignals.MCP.client_name(conn.body_params)
      )
    end

    # Uses the same matching as tracked routes: the route template when one
    # matched, otherwise the raw path (only for prefix selection).
    defp mcp_route?(_conn, _route_template, []), do: false

    defp mcp_route?(conn, route_template, prefixes) do
      {_route, mcp_route?} =
        ClientSignals.Request.tracked_route(
          conn.method,
          route_template,
          conn.request_path,
          prefixes
        )

      mcp_route?
    end

    defp first_req_header(conn, header) do
      case get_req_header(conn, header) do
        [value | _] -> value
        _ -> nil
      end
    end

    defp notify_request_observer({module, function, args}, labels)
         when is_atom(module) and is_atom(function) and is_list(args) do
      apply(module, function, [labels | args])
    end

    defp route_template(nil, _conn), do: nil

    defp route_template({module, function, args}, conn)
         when is_atom(module) and is_atom(function) and is_list(args) do
      apply(module, function, [conn | args])
    end
  end
end
