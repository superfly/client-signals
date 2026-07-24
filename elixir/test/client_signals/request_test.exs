defmodule ClientSignals.RequestTest do
  use ExUnit.Case, async: true

  alias ClientSignals.Request

  describe "classify/3" do
    test "requires the interactive instrumentation sentinel" do
      assert Request.classify(nil, "codex", "true") == %{
               operator: "uninstrumented",
               agent: "none"
             }

      assert Request.classify("maybe", "codex", nil) == %{
               operator: "uninstrumented",
               agent: "none"
             }
    end

    test "CI takes precedence and preserves a known agent" do
      assert Request.classify("false", "codex", "true") == %{
               operator: "ci",
               agent: "codex"
             }
    end

    test "classifies known agents" do
      assert Request.classify("true", "claude-code", nil) == %{
               operator: "agent",
               agent: "claude-code"
             }
    end

    test "bounds unknown sanitized declarations" do
      assert Request.classify("false", "my-agent", nil) == %{
               operator: "agent",
               agent: "other"
             }
    end

    test "ignores invalid agents" do
      assert Request.classify("false", "bad agent value", nil) == %{
               operator: "automated_unattributed",
               agent: "none"
             }
    end

    test "classifies interactive and automated unattributed requests" do
      assert Request.classify("true", nil, nil) == %{
               operator: "interactive",
               agent: "none"
             }

      assert Request.classify("false", nil, nil) == %{
               operator: "automated_unattributed",
               agent: "none"
             }
    end
  end

  describe "tracked_api_route/4" do
    test "combines the method and matched route template" do
      assert Request.tracked_api_route(
               "post",
               "/v1/apps/:app/machines/:id",
               "/v1/apps/my-app/machines/123",
               ["/v1"]
             ) == {"POST /v1/apps/:app/machines/:id", true}
    end

    test "matches prefixes on path boundaries" do
      assert Request.tracked_api_route("GET", "/v10/apps", "/v10/apps", ["/v1"]) ==
               {"", false}
    end

    test "uses a bounded label for unmatched API requests" do
      assert Request.tracked_api_route(
               "get",
               nil,
               "/api/v1/not-a-route/123",
               ["/api/v1"]
             ) == {"GET unmatched", true}
    end

    test "ignores unmatched non-API requests" do
      assert Request.tracked_api_route("GET", nil, "/dashboard", ["/api/v1"]) ==
               {"", false}
    end
  end
end
