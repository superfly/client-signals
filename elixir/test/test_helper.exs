ExUnit.start()

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
