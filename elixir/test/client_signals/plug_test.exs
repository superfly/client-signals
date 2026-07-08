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

  describe "call/2" do
    test "returns the conn unchanged" do
      conn = build_conn([{"fly-client-interactive", "true"}])

      assert ClientSignalsPlug.call(conn, ClientSignalsPlug.init([])) == conn
    end

    test "does not raise when there are no client signal headers" do
      conn = build_conn([])

      assert ClientSignalsPlug.call(conn, ClientSignalsPlug.init([])) == conn
    end
  end
end
