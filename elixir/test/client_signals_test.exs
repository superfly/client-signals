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

defmodule SimpleJSON do
  def decode!(json) do
    {value, rest} = parse_value(trim(json))

    case trim(rest) do
      "" -> value
      other -> raise "unexpected trailing JSON: #{inspect(other)}"
    end
  end

  defp parse_value(<<"[", rest::binary>>), do: parse_array(trim(rest), [])
  defp parse_value(<<"{", rest::binary>>), do: parse_object(trim(rest), %{})
  defp parse_value(<<"\"", rest::binary>>), do: parse_string(rest, "")
  defp parse_value(<<"true", rest::binary>>), do: {true, rest}
  defp parse_value(<<"false", rest::binary>>), do: {false, rest}

  defp parse_array(<<"]", rest::binary>>, acc), do: {Enum.reverse(acc), rest}

  defp parse_array(json, acc) do
    {value, rest} = parse_value(trim(json))

    case trim(rest) do
      <<",", next::binary>> -> parse_array(trim(next), [value | acc])
      <<"]", next::binary>> -> {Enum.reverse([value | acc]), next}
    end
  end

  defp parse_object(<<"}", rest::binary>>, acc), do: {acc, rest}

  defp parse_object(json, acc) do
    {key, rest} = parse_value(trim(json))
    <<":", after_colon::binary>> = trim(rest)
    {value, rest} = parse_value(trim(after_colon))

    case trim(rest) do
      <<",", next::binary>> -> parse_object(trim(next), Map.put(acc, key, value))
      <<"}", next::binary>> -> {Map.put(acc, key, value), next}
    end
  end

  defp parse_string(<<"\"", rest::binary>>, acc), do: {acc, rest}
  defp parse_string(<<"\\\"", rest::binary>>, acc), do: parse_string(rest, acc <> "\"")
  defp parse_string(<<"\\\\", rest::binary>>, acc), do: parse_string(rest, acc <> "\\")

  defp parse_string(<<char::utf8, rest::binary>>, acc),
    do: parse_string(rest, acc <> <<char::utf8>>)

  defp trim(value), do: String.trim_leading(value)
end
