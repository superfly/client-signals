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
    def init(opts) do
      service = Keyword.get(opts, :service)
      tracked_route_prefixes = Keyword.get(opts, :tracked_route_prefixes, [])
      configured_request_observer = Keyword.get(opts, :request_observer)
      route_template_provider = Keyword.get(opts, :route_template_provider)

      metrics_configured? =
        not is_nil(service) or tracked_route_prefixes != [] or
          not is_nil(configured_request_observer) or not is_nil(route_template_provider)

      request_observer =
        if metrics_configured? do
          configured_request_observer || {ClientSignals.RequestMetrics, :observe, []}
        end

      if metrics_configured? and
           (not is_binary(service) or service == "" or tracked_route_prefixes == [] or
              is_nil(route_template_provider)) do
        raise ArgumentError,
              "service, tracked_route_prefixes, and route_template_provider are all required " <>
                "when client-signal request observation is enabled"
      end

      %{
        service: service,
        tracked_route_prefixes: tracked_route_prefixes,
        request_observer: request_observer,
        route_template_provider: route_template_provider
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

    defp maybe_register_request_observer(conn, %{request_observer: nil}), do: conn

    defp maybe_register_request_observer(conn, opts) do
      register_before_send(conn, fn conn ->
        route_template = route_template(opts.route_template_provider, conn)

        case ClientSignals.Request.tracked_route(
               conn.method,
               route_template,
               conn.request_path,
               opts.tracked_route_prefixes
             ) do
          {route, true} ->
            classification =
              ClientSignals.Request.classify(
                first_req_header(conn, @interactive_header),
                first_req_header(conn, @agent_header),
                first_req_header(conn, @ci_header)
              )

            labels =
              classification
              |> Map.put(:service, opts.service)
              |> Map.put(:route, route)

            notify_request_observer(opts.request_observer, labels)
            conn

          {"", false} ->
            conn
        end
      end)
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

    defp route_template({module, function, args}, conn)
         when is_atom(module) and is_atom(function) and is_list(args) do
      apply(module, function, [conn | args])
    end
  end
end
