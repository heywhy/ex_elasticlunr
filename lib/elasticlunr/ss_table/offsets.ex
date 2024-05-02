defmodule Elasticlunr.SSTable.Offsets do
  @moduledoc """
  |---------------------------------|
  | offset(8B) | key_size(8B) | key |
  |---------------------------------|
  """
  alias Elasticlunr.Encoding

  defstruct [:entries]

  @type t :: %__MODULE__{entries: Treex.t()}

  @spec new() :: t()
  def new, do: struct!(__MODULE__, entries: Treex.empty())

  @spec set(t(), binary(), pos_integer()) :: t()
  def set(%__MODULE__{entries: e} = m, key, offset) do
    %{m | entries: Treex.enter(e, key, offset)}
  end

  @spec get(t(), binary()) :: {pos_integer(), pos_integer() | nil}
  def get(%__MODULE__{entries: {_, tree}}, key) do
    tree
    |> find_boundary(key)
    |> case do
      {s, e} when s > e -> {s, nil}
      {s, e} = offsets when s < e -> offsets
      {o, o} = offsets -> offsets
    end
  end

  @spec encode(t()) :: iodata()
  def encode(%__MODULE__{entries: tree}) do
    tree
    |> Treex.stream()
    |> Stream.map(fn {key, offset} ->
      []
      |> Encoding.put_int64(offset)
      |> Encoding.put_size_prefixed(key)
    end)
    |> Enum.to_list()
  end

  @spec decode!(binary()) :: t() | no_return()
  def decode!(binary) when is_binary(binary) do
    fun = fn
      <<>>, _fun, acc ->
        acc

      binary, fun, offsets ->
        {offset, binary} = Encoding.chop_int64!(binary)
        {key, binary} = Encoding.chop_size_prefixed!(binary)

        offsets
        |> set(key, offset)
        |> then(&fun.(binary, fun, &1))
    end

    binary
    |> fun.(fun, new())
    |> then(&%{&1 | entries: Treex.balance(&1.entries)})
  end

  defp find_boundary(node, key, acc \\ nil)
  defp find_boundary({key, offset, _smaller, _bigger}, key, _acc), do: {offset, offset}

  defp find_boundary({key1, offset, _smaller, bigger}, key, prev)
       when key > key1 do
    case bigger do
      nil -> {offset, prev}
      bigger -> find_boundary(bigger, key, offset)
    end
  end

  defp find_boundary({key1, offset, smaller, _bigger}, key, prev)
       when key < key1 do
    case smaller do
      nil -> {prev, offset}
      smaller -> find_boundary(smaller, key, offset)
    end
  end
end
