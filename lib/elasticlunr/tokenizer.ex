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

    separator
    |> Regex.scan(str, return: :index)
    |> run_split(str, 0, [])
  end

  defp run_split([], str, last_index, tokens) do
    length = String.length(str) - 1

    token =
      str
      |> String.slice(last_index..length)
      |> to_token(last_index, length)

    tokens ++ [token]
  end

  defp run_split([head | tail], str, last_index, tokens) do
    [{index, count}] = head
    index = index - 1
    sub_str = String.slice(str, last_index..index)
    token = to_token(sub_str, last_index, index)
    tokens = tokens ++ [token]
    last_index = last_index + String.length(sub_str) + count

    run_split(tail, str, last_index, tokens)
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
