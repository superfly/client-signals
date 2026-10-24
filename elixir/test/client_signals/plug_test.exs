defmodule ClientSignals.PlugTest do
  use ExUnit.Case, async: true

  alias ClientSignals.Plug, as: ClientSignalsPlug

  defp build_conn(headers) do
    conn = Plug.Test.conn(:get, "/")

    Enum.reduce(headers, conn, fn {k, v}, conn ->
      Plug.Conn.put_req_header(conn, k, v)
    end)
  end

  describe "client_signal_attributes/1" do
    test "collects all headers when present" do
      conn =
        build_conn([
          {"fly-client-interactive", "true"},
          {"fly-client-parent", "shell"},
          {"fly-client-agent", "claude-code"},
          {"fly-client-agent-source", "env:CLAUDECODE"},
          {"fly-client-ci", "true"}
        ])

      attrs = ClientSignalsPlug.client_signal_attributes(conn) |> Map.new()

      assert attrs == %{
               "fly.client.interactive" => true,
               "fly.client.parent" => "shell",
               "fly.client.agent" => "claude-code",
               "fly.client.agent_source" => "env:CLAUDECODE",
               "fly.client.ci" => true
             }
    end

    test "returns nothing when no headers are present" do
      assert ClientSignalsPlug.client_signal_attributes(build_conn([])) == []
    end

    test "only includes attributes for headers actually present" do
      conn =
        build_conn([{"fly-client-interactive", "false"}, {"fly-client-parent", "python"}])

      attrs = ClientSignalsPlug.client_signal_attributes(conn) |> Map.new()

      assert attrs == %{
               "fly.client.interactive" => false,
               "fly.client.parent" => "python"
             }
    end

    test "ignores unparseable boolean values" do
      conn = build_conn([{"fly-client-interactive", "maybe"}, {"fly-client-ci", "nope"}])

      assert ClientSignalsPlug.client_signal_attributes(conn) == []
    end

    test "ignores an empty or whitespace-only string value" do
      conn = build_conn([{"fly-client-parent", "   "}])

      assert ClientSignalsPlug.client_signal_attributes(conn) == []
    end

    test "trims whitespace from string and boolean values" do
      conn =
        build_conn([{"fly-client-parent", "  shell  "}, {"fly-client-interactive", " true\n"}])

      attrs = ClientSignalsPlug.client_signal_attributes(conn) |> Map.new()

      assert attrs == %{
               "fly.client.parent" => "shell",
               "fly.client.interactive" => true
             }
    end

    test "truncates string values longer than the max attribute length" do
      long_value = String.duplicate("a", 500)
      conn = build_conn([{"fly-client-parent", long_value}])

      attrs = ClientSignalsPlug.client_signal_attributes(conn) |> Map.new()

      assert String.length(attrs["fly.client.parent"]) == 256
    end
  end

  describe "mcp_client_attributes/1" do
    test "returns only bounded client attributes" do
      conn =
        Plug.Test.conn(:post, "/mcp", %{
          "method" => "initialize",
          "params" => %{"clientInfo" => %{"name" => "my-private-tool 1.0"}}
        })
        |> Plug.Conn.put_req_header("user-agent", "python-httpx/0.28.1")

      assert ClientSignalsPlug.mcp_client_attributes(conn) == [
               {"fly.client.mcp_client", "other"},
               {"fly.client.mcp_source", "client_info"}
             ]
    end

    test "prefers the vendor header" do
      conn =
        build_conn([{"user-agent", "Claude-User"}, {"x-anthropic-client", "ClaudeCode"}])

      assert ClientSignalsPlug.mcp_client_attributes(conn) == [
               {"fly.client.mcp_client", "claude-code"},
               {"fly.client.mcp_source", "vendor_header"}
             ]
    end

    test "returns nothing when no client is identified" do
      assert ClientSignalsPlug.mcp_client_attributes(build_conn([{"user-agent", "curl/8.0"}])) ==
               []
    end
  end

  describe "call/2" do
    test "returns the conn unchanged" do
      conn = build_conn([{"fly-client-interactive", "true"}])

      assert ClientSignalsPlug.call(conn, ClientSignalsPlug.init([])) == conn
    end

    test "does not raise when there are no client signal headers" do
      conn = build_conn([])

      assert ClientSignalsPlug.call(conn, ClientSignalsPlug.init([])) == conn
    end

    test "observes configured routes after routing" do
      opts =
        ClientSignalsPlug.init(
          service: "sprites-api",
          tracked_route_prefixes: ["/v1", "/api/v1"],
          request_observer: {__MODULE__, :observe_request, [self()]},
          route_template_provider: {__MODULE__, :route_template, ["/v1/sprites/:name"]}
        )

      conn =
        build_conn([
          {"fly-client-interactive", "false"},
          {"fly-client-agent", "codex"}
        ])
        |> ClientSignalsPlug.call(opts)
        |> Plug.Conn.send_resp(200, "ok")

      assert conn.state == :sent

      assert_receive {:observed_request,
                      %{
                        service: "sprites-api",
                        route: "GET /v1/sprites/:name",
                        operator: "agent",
                        agent: "codex"
                      }}
    end

    test "uses the canonical telemetry observer by default" do
      handler_id = {__MODULE__, self()}

      :telemetry.attach(
        handler_id,
        [:client_signals, :request],
        &__MODULE__.handle_event/4,
        self()
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      opts =
        ClientSignalsPlug.init(
          service: "ui-ex",
          tracked_route_prefixes: ["/api/v1"],
          route_template_provider:
            {__MODULE__, :route_template, ["/api/v1/organizations/:org_slug"]}
        )

      build_conn([{"fly-client-interactive", "true"}])
      |> ClientSignalsPlug.call(opts)
      |> Plug.Conn.send_resp(200, "ok")

      assert_receive {
        [:client_signals, :request],
        %{count: 1},
        %{
          service: "ui-ex",
          route: "GET /api/v1/organizations/:org_slug",
          operator: "interactive",
          agent: "none"
        }
      }
    end

    test "does not observe routes outside the configured prefixes" do
      opts =
        ClientSignalsPlug.init(
          service: "ui-ex",
          tracked_route_prefixes: ["/api/v1"],
          request_observer: {__MODULE__, :observe_request, [self()]},
          route_template_provider: {__MODULE__, :route_template, ["/dashboard/:organization_id"]}
        )

      build_conn([{"fly-client-interactive", "true"}])
      |> ClientSignalsPlug.call(opts)
      |> Plug.Conn.send_resp(200, "ok")

      refute_receive {:observed_request, _labels}
    end

    test "uses a bounded route for unmatched requests under a tracked prefix" do
      opts =
        ClientSignalsPlug.init(
          service: "ui-ex",
          tracked_route_prefixes: ["/api/v1"],
          request_observer: {__MODULE__, :observe_request, [self()]},
          route_template_provider: {__MODULE__, :route_template, [nil]}
        )

      Plug.Test.conn(:delete, "/api/v1/not-a-route/123")
      |> ClientSignalsPlug.call(opts)
      |> Plug.Conn.send_resp(404, "not found")

      assert_receive {:observed_request,
                      %{
                        service: "ui-ex",
                        route: "DELETE unmatched",
                        operator: "uninstrumented",
                        agent: "none"
                      }}
    end

    test "classifies MCP routes with inferred client identity" do
      opts =
        ClientSignalsPlug.init(
          service: "flyio-mcp",
          tracked_route_prefixes: ["/mcp", "/api/v1"],
          mcp_route_prefixes: ["/mcp"],
          request_observer: {__MODULE__, :observe_request, [self()]},
          route_template_provider: {__MODULE__, :route_template, ["/mcp"]}
        )

      Plug.Test.conn(:post, "/mcp", %{
        "method" => "initialize",
        "params" => %{"clientInfo" => %{"name" => "Zed"}}
      })
      |> Plug.Conn.put_req_header("user-agent", "node")
      |> ClientSignalsPlug.call(opts)
      |> Plug.Conn.send_resp(200, "ok")

      assert_receive {:observed_request,
                      %{
                        service: "flyio-mcp",
                        route: "POST /mcp",
                        operator: "mcp",
                        agent: "zed"
                      }}
    end

    test "self-reported signals win on MCP routes" do
      opts =
        ClientSignalsPlug.init(
          service: "flyio-mcp",
          tracked_route_prefixes: ["/mcp"],
          mcp_route_prefixes: ["/mcp"],
          request_observer: {__MODULE__, :observe_request, [self()]},
          route_template_provider: {__MODULE__, :route_template, ["/mcp"]}
        )

      build_conn([
        {"fly-client-interactive", "true"},
        {"user-agent", "claude-code/2.1.309 (cli)"}
      ])
      |> ClientSignalsPlug.call(opts)
      |> Plug.Conn.send_resp(200, "ok")

      assert_receive {:observed_request, %{operator: "interactive", agent: "none"}}
    end

    test "does not infer MCP clients outside MCP routes" do
      opts =
        ClientSignalsPlug.init(
          service: "flyio-mcp",
          tracked_route_prefixes: ["/mcp", "/api/v1"],
          mcp_route_prefixes: ["/mcp"],
          request_observer: {__MODULE__, :observe_request, [self()]},
          route_template_provider: {__MODULE__, :route_template, ["/api/v1/apps"]}
        )

      build_conn([{"user-agent", "Claude-User"}])
      |> ClientSignalsPlug.call(opts)
      |> Plug.Conn.send_resp(200, "ok")

      assert_receive {:observed_request,
                      %{route: "GET /api/v1/apps", operator: "uninstrumented", agent: "none"}}
    end

    test "uses the request path for unmatched MCP routes and tolerates unfetched bodies" do
      opts =
        ClientSignalsPlug.init(
          service: "flyio-mcp",
          tracked_route_prefixes: ["/mcp"],
          mcp_route_prefixes: ["/mcp"],
          request_observer: {__MODULE__, :observe_request, [self()]},
          route_template_provider: {__MODULE__, :route_template, [nil]}
        )

      conn = build_conn([{"user-agent", "Cursor/3.20.21 (darwin arm64)"}])

      %{conn | request_path: "/mcp", body_params: %Plug.Conn.Unfetched{aspect: :body_params}}
      |> ClientSignalsPlug.call(opts)
      |> Plug.Conn.send_resp(200, "ok")

      assert_receive {:observed_request,
                      %{route: "GET unmatched", operator: "mcp", agent: "cursor"}}
    end

    test "allows MCP span attributes without request observation" do
      opts = ClientSignalsPlug.init(mcp_route_prefixes: ["/mcp"])

      conn =
        build_conn([{"user-agent", "Claude-User"}])
        |> ClientSignalsPlug.call(opts)

      assert [_before_send] = conn.private[:before_send]
      assert Plug.Conn.send_resp(conn, 200, "ok").state == :sent
    end

    test "rejects invalid MCP route prefixes" do
      assert_raise ArgumentError, fn ->
        ClientSignalsPlug.init(mcp_route_prefixes: "/mcp")
      end

      assert_raise ArgumentError, fn ->
        ClientSignalsPlug.init(mcp_route_prefixes: [:mcp])
      end
    end

    test "requires the complete request observation configuration" do
      assert_raise ArgumentError, fn ->
        ClientSignalsPlug.init(service: "ui-ex", tracked_route_prefixes: ["/api/v1"])
      end
    end
  end

  def observe_request(labels, test_pid), do: send(test_pid, {:observed_request, labels})
  def route_template(_conn, route_template), do: route_template

  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {event, measurements, metadata})
  end
end
