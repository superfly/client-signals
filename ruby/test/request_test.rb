# frozen_string_literal: true

require_relative "test_helper"

class ClientSignalsRequestTest < Minitest::Test
  include FixtureHelpers

  Request = ClientSignals::Request

  def test_classification_matches_the_shared_fixtures
    fixture("request-classification-fixtures.json").each do |f|
      got = Request.classify_headers(f["headers"])

      assert_equal f["want"]["operator"], got[:operator], f["name"]
      assert_equal f["want"]["agent"], got[:agent], f["name"]
    end
  end

  def test_route_selection_matches_the_shared_fixtures
    fixture("route-fixtures.json").each do |f|
      route, tracked = Request.tracked_route(
        f["method"], f["routeTemplate"], f["requestPath"], f["prefixes"]
      )

      assert_equal f["wantRoute"], route, f["name"]
      assert_equal f["tracked"], tracked, f["name"]
    end
  end

  def test_classify_takes_the_three_values_directly
    assert_equal(
      { operator: "agent", agent: "codex" },
      Request.classify("false", "codex", nil)
    )
  end

  def test_a_missing_sentinel_is_uninstrumented_whatever_else_arrived
    assert_equal(
      { operator: "uninstrumented", agent: "none" },
      Request.classify(nil, "claude-code", "true")
    )
  end

  def test_an_unknown_agent_is_bounded
    assert_equal "other", Request.normalize_agent("some-new-agent")
  end

  def test_an_agent_that_is_not_a_bare_tool_name_is_none
    assert_equal "none", Request.normalize_agent("claude code/1.0")
    assert_equal "none", Request.normalize_agent("-leading-dash")
    assert_equal "none", Request.normalize_agent("a" * 65)
    assert_equal "none", Request.normalize_agent(nil)
  end

  def test_classify_headers_reads_a_hash_with_canonical_names
    got = Request.classify_headers(
      "Fly-Client-Interactive" => "true",
      "Fly-Client-Agent" => "Claude-Code",
    )

    assert_equal({ operator: "agent", agent: "claude-code" }, got)
  end

  def test_prefix_matching_respects_segment_boundaries
    _, tracked = Request.tracked_route("GET", nil, "/v10/apps", ["/v1"])
    refute tracked, "/v1 must not match /v10"

    _, tracked = Request.tracked_route("GET", nil, "/v1/apps", ["/v1"])
    assert tracked
  end
end
