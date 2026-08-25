# frozen_string_literal: true

require_relative "test_helper"

class ClientSignalsTest < Minitest::Test
  include FixtureHelpers

  def test_marker_table_matches_the_shared_spec
    want = fixture("markers.json").map do |marker|
      { "agent" => marker["agent"], "env" => marker["env"], "kind" => marker["kind"], "values" => marker["values"] }
    end

    got = ClientSignals::KNOWN_MARKERS.map do |marker|
      kind = marker[:kind] == :exact_value ? "exactValue" : "presence"
      { "agent" => marker[:agent], "env" => marker[:env], "kind" => kind, "values" => marker[:values] }
    end

    assert_equal want, got, "the mirrored marker table has drifted from spec/markers.json"
  end

  def test_sanitize_invoked_by_matches_the_shared_fixtures
    fixture("sanitize-fixtures.json").each do |f|
      name, ok = ClientSignals.sanitize_invoked_by(f["input"])

      assert_equal f["want"], name, f["name"]
      assert_equal f["valid"], ok, f["name"]
    end
  end

  def test_parent_classification_matches_the_shared_fixtures
    fixture("parent-fixtures.json").each do |f|
      assert_equal f["want"], ClientSignals.classify_parent_name(f["raw"]), f["raw"].inspect
    end
  end

  def test_operator_matches_the_shared_fixtures
    fixture("operator-fixtures.json").each do |f|
      assert_equal f["want"], signals_from_fixture(f["signals"]).operator, f["name"]
    end
  end

  def test_headers_and_user_agent_suffix_match_the_shared_fixtures
    fixture("header-fixtures.json").each do |f|
      signals = signals_from_fixture(f["signals"])

      assert_equal f["headers"], signals.headers(prefix: f["prefix"]), f["name"]
      assert_equal f["userAgentSuffix"], signals.user_agent_suffix, f["name"]
    end
  end

  def test_apply_headers_merges_into_the_target
    signals = ClientSignals::Signals.new(
      interactive: false, parent: "shell", agent: "", agent_source: "", ci: false
    )
    target = { "User-Agent" => "flyctl/1.2.3" }

    signals.apply_headers(target)

    assert_equal "flyctl/1.2.3", target["User-Agent"]
    assert_equal "false", target["Fly-Client-Interactive"]
    assert_equal "shell", target["Fly-Client-Parent"]
    refute target.key?("Fly-Client-Agent"), "absent agent must not produce a header"
    refute target.key?("Fly-Client-CI"), "absent CI must not produce a header"
  end

  def test_detect_reads_a_known_marker
    with_env("CLAUDECODE" => "1") do
      signals = ClientSignals.detect

      assert_equal "claude-code", signals.agent
      assert_equal "env:CLAUDECODE", signals.agent_source
    end
  end

  def test_detect_ignores_a_known_marker_set_to_the_wrong_value
    with_env("CLAUDECODE" => "0") do
      assert_equal "", ClientSignals.detect.agent
    end
  end

  def test_fly_invoked_by_wins_over_the_marker_table
    with_env("FLY_INVOKED_BY" => "Some-Harness", "CLAUDECODE" => "1") do
      signals = ClientSignals.detect

      assert_equal "some-harness", signals.agent
      assert_equal "env:FLY_INVOKED_BY", signals.agent_source
    end
  end

  def test_an_unusable_fly_invoked_by_falls_through_to_the_marker_table
    with_env("FLY_INVOKED_BY" => "not a bare name", "CLAUDECODE" => "1") do
      assert_equal "claude-code", ClientSignals.detect.agent
    end
  end

  def test_ci_is_detected_by_presence_not_by_value
    with_env("CI" => "") { assert ClientSignals.detect.ci }
    with_env("GITHUB_ACTIONS" => "true") { assert ClientSignals.detect.ci }
    with_env({}) { refute ClientSignals.detect.ci }
  end

  def test_parent_is_always_one_of_the_buckets
    assert_includes %w[node python shell other], ClientSignals.detect.parent
  end

  def test_detect_once_caches
    ClientSignals.reset_cache_for_test

    first = with_env("CLAUDECODE" => "1") { ClientSignals.detect_once }
    second = with_env({}) { ClientSignals.detect_once }

    assert_same first, second, "detect_once must not re-read the environment"
  ensure
    ClientSignals.reset_cache_for_test
  end
end
