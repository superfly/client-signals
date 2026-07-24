defmodule ClientSignalsTest do
  use ExUnit.Case, async: false

  @root Path.expand("../..", __DIR__)

  test "known markers match shared spec" do
    assert ClientSignals.known_markers() == fixture("markers.json")
  end

  test "sanitize_invoked_by follows shared fixtures" do
    for case <- fixture("sanitize-fixtures.json") do
      {got, ok} = ClientSignals.sanitize_invoked_by(case["input"])
      assert ok == case["valid"], case["name"]
      assert got == case["want"], case["name"]
    end
  end

  test "classify_parent_name follows shared fixtures" do
    for case <- fixture("parent-fixtures.json") do
      assert ClientSignals.classify_parent_name(case["raw"]) == case["want"]
    end
  end

  test "headers_for and user_agent_suffix follow shared fixtures" do
    for case <- fixture("header-fixtures.json") do
      assert ClientSignals.headers_for(case["signals"], case["prefix"]) == case["headers"]
      assert ClientSignals.user_agent_suffix(case["signals"]) == case["userAgentSuffix"]
    end
  end

  test "operator follows shared fixtures" do
    for case <- fixture("operator-fixtures.json") do
      assert ClientSignals.operator(case["signals"]) == case["want"], case["name"]
    end
  end

  test "apply_headers merges signal headers" do
    signals = fixture("header-fixtures.json") |> hd() |> Map.fetch!("signals")
    headers = ClientSignals.apply_headers(%{}, signals)
    assert headers["Fly-Client-Agent"] == "claude-code"
  end

  test "detect_once caches the first value" do
    with_clean_agent_env(fn ->
      ClientSignals.reset_cached_for_test()
      System.put_env("FLY_INVOKED_BY", "cached-tool")
      first = ClientSignals.detect_once()
      System.put_env("FLY_INVOKED_BY", "different-tool")
      second = ClientSignals.detect_once()
      assert second == first
      assert second.agent == "cached-tool"
      ClientSignals.reset_cached_for_test()
    end)
  end

  test "detect returns finite values" do
    signals = ClientSignals.detect()
    assert is_boolean(signals.interactive)
    assert signals.parent in ["node", "python", "shell", "other"]
    assert is_binary(signals.agent)
    assert is_binary(signals.agent_source)
    assert is_boolean(signals.ci)
  end

  defp fixture(name) do
    @root
    |> Path.join("spec/#{name}")
    |> File.read!()
    |> SimpleJSON.decode!()
  end

  defp with_clean_agent_env(fun) do
    names = ["FLY_INVOKED_BY", "AGENT"] ++ Enum.map(ClientSignals.known_markers(), & &1["env"])
    saved = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.delete_env/1)

    try do
      fun.()
    after
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
  end
end
