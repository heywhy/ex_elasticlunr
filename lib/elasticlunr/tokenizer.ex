defmodule Elasticlunr.Tokenizer do
  alias Elasticlunr.Token

  @default_separator ~r/[\s\-]+/

  @spec tokenize(binary() | number(), Regex.t()) :: list(Token.t())
  def tokenize(str, separator \\ @default_separator)
  def tokenize(str, separator) when is_binary(str), do: split(str, separator)

  def tokenize(num, separator) when is_number(num) do
    num
    |> to_string()
    |> split(separator)
  end

  defp split(str, separator) do
    str = String.trim(str)

    slice_end = 0
    slice_start = 0
    str_length = String.length(str)

    run_split(str, separator, slice_start, slice_end, str_length, [])
  end

  defp run_split(str, separator, slice_start, slice_end, str_length, tokens) when slice_end <= str_length do
    char = String.at(str, slice_end)
    slice_length = slice_end - slice_start

    with true <- match_string?(char, separator) || slice_end == str_length,
          true <- slice_length > 0 do
      token_str = String.slice(str, slice_start..slice_end)
      token = to_token(token_str, slice_start, slice_length)
      tokens = [token] ++ tokens
      slice_start = slice_end + 1
      run_split(str, separator, slice_start, slice_end + 1, str_length, tokens)
    else
      false ->
        run_split(str, separator, slice_start, slice_end + 1, str_length, tokens)
    end
  end
  defp run_split(_str, _separator, _slice_start, _slice_end, _str_length, tokens) do
    tokens
  end

  defp match_string?(nil, _separator), do: false
  defp match_string?(char, separator) do
    String.match?(char, separator)
  end

  defp to_token(str, start_index, end_index) do
    str
    |> String.downcase()
    |> Token.new(%{
      end: end_index,
      start: start_index
    })
  end
end
