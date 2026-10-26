defmodule ClientSignals.MCPTest do
  use ExUnit.Case, async: true

  alias ClientSignals.MCP
  alias ClientSignals.Request

  @root Path.expand("../../..", __DIR__)

  test "rules match the shared spec, in order" do
    assert MCP.rules() == fixture("mcp-clients.json")["rules"]
  end

  test "labels are the distinct rule clients" do
    assert MCP.labels() ==
             fixture("mcp-clients.json")["rules"] |> Enum.map(& &1["client"]) |> Enum.uniq()
  end

  test "classify_client/3 and classify_request/6 follow shared MCP fixtures" do
    for case <- fixture("mcp-client-fixtures.json") do
      headers = case["headers"]
      want = case["want"]

      assert MCP.classify_client(
               headers["User-Agent"],
               headers["X-Anthropic-Client"],
               case["clientName"]
             ) == %{client: want["client"], source: want["source"]},
             case["name"]

      assert MCP.classify_request(
               headers["Fly-Client-Interactive"],
               headers["Fly-Client-Agent"],
               headers["Fly-Client-CI"],
               headers["User-Agent"],
               headers["X-Anthropic-Client"],
               case["clientName"]
             ) == %{operator: want["operator"], agent: want["agent"]},
             case["name"]
    end
  end

  test "classify_request/6 matches classify/3 without MCP inputs" do
    for case <- fixture("request-classification-fixtures.json") do
      headers = case["headers"]

      classification =
        Request.classify(
          headers["Fly-Client-Interactive"],
          headers["Fly-Client-Agent"],
          headers["Fly-Client-CI"]
        )

      assert MCP.classify_request(
               headers["Fly-Client-Interactive"],
               headers["Fly-Client-Agent"],
               headers["Fly-Client-CI"],
               nil,
               nil,
               nil
             ) == classification,
             case["name"]

      assert classification == %{
               operator: case["want"]["operator"],
               agent: case["want"]["agent"]
             },
             case["name"]
    end
  end

  test "every label is a sanitized, lowercase, known agent" do
    for label <- MCP.labels() do
      assert ClientSignals.sanitize_invoked_by(label) == {label, true}
      assert label == String.downcase(label)
      assert Request.classify("false", label, nil) == %{operator: "agent", agent: label}
    end
  end

  test "only ever returns bounded clients and sources" do
    clients = ["", "other" | MCP.labels()]
    sources = ~w(vendor_header user_agent client_info none)

    inputs = [
      nil,
      "",
      "secret-token-abc123",
      "Mozilla/5.0 (Macintosh)",
      "claude-code/2.1.309 (cli)",
      String.duplicate("x", 1_000)
    ]

    for user_agent <- inputs, vendor_client <- inputs, client_name <- inputs do
      result = MCP.classify_client(user_agent, vendor_client, client_name)
      assert result.client in clients
      assert result.source in sources
    end
  end

  test "treats non-binary inputs as absent" do
    assert MCP.classify_client(123, %{}, [:cursor]) == %{client: "", source: "none"}
  end

  describe "client_name/1" do
    test "reads clientInfo from initialize requests" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "params" => %{"clientInfo" => %{"name" => "claude-code", "version" => "2.1.309"}}
      }

      assert MCP.client_name(request) == "claude-code"
      assert MCP.client_name(request["params"]) == "claude-code"
    end

    test "prefers _meta clientInfo on any request" do
      request = %{
        "method" => "tools/call",
        "params" => %{
          "_meta" => %{"io.modelcontextprotocol/clientInfo" => %{"name" => "cursor-vscode"}},
          "clientInfo" => %{"name" => "ignored"}
        }
      }

      assert MCP.client_name(request) == "cursor-vscode"
      assert MCP.client_name(request["params"]) == "cursor-vscode"
    end

    test "ignores params clientInfo outside initialize" do
      request = %{"method" => "tools/call", "params" => %{"clientInfo" => %{"name" => "zed"}}}

      assert MCP.client_name(request) == nil
      assert MCP.client_name(%{"method" => "tools/list"}) == nil
    end

    test "returns nil for batches, structs, and malformed values" do
      assert MCP.client_name([%{"method" => "initialize"}]) == nil
      assert MCP.client_name(%{"_json" => [%{"method" => "initialize"}]}) == nil
      assert MCP.client_name(%URI{}) == nil
      assert MCP.client_name(nil) == nil
      assert MCP.client_name(%{"clientInfo" => %{"name" => 1}}) == nil
      assert MCP.client_name(%{"clientInfo" => "zed"}) == nil
      assert MCP.client_name(%{"method" => "initialize", "params" => "zed"}) == nil
    end
  end

  defp fixture(name) do
    @root
    |> Path.join("spec/#{name}")
    |> File.read!()
    |> SimpleJSON.decode!()
  end
end
