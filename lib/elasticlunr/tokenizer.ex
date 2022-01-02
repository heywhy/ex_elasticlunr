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
    slice_end = 0
    slice_start = 0
    str_length = String.length(str)

    str
    |> String.downcase()
    |> run_split(separator, slice_start, slice_end, str_length, [])
  end

  defp run_split(str, separator, slice_start, slice_end, str_length, tokens)
       when slice_end <= str_length do
    char = String.at(str, slice_end)
    slice_length = slice_end - slice_start

    with true <- match_string?(char, separator) || slice_end == str_length,
         {:s, true} <- {:s, slice_length > 0} do
      token =
        str
        |> String.slice(slice_start, slice_length)
        |> to_token(slice_start, slice_length)

      tokens = tokens ++ [token]
      slice_start = slice_end + 1
      run_split(str, separator, slice_start, slice_end + 1, str_length, tokens)
    else
      {:s, false} ->
        index = slice_end + 1
        run_split(str, separator, index, index, str_length, tokens)

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
    Token.new(str, %{
      end: end_index,
      start: start_index
    })
  end
end
