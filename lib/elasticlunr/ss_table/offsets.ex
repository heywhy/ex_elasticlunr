defmodule Elasticlunr.SSTable.Offsets do
  @moduledoc """
  |---------------------------------|
  | offset(8B) | key_size(8B) | key |
  |---------------------------------|
  """

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
      <<offset::unsigned-integer-size(64), byte_size(key)::unsigned-integer-size(64),
        key::binary>>
    end)
    |> Enum.to_list()
  end

  @spec decode(binary()) :: {:ok, t()}
  def decode(binary) when is_binary(binary) do
    fun = fn
      <<>>, _fun, acc ->
        acc

      <<offset::unsigned-integer-size(64), key_size::unsigned-integer-size(64),
        key::binary-size(key_size), rest::binary>>,
      fun,
      offsets ->
        offsets
        |> set(key, offset)
        |> then(&fun.(rest, fun, &1))
    end

    binary
    |> fun.(fun, new())
    |> then(&%{&1 | entries: Treex.balance(&1.entries)})
    |> then(&{:ok, &1})
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
