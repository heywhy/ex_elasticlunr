defmodule Elasticlunr.SSTable.Offsets do
  alias Elasticlunr.Fs

  @moduledoc """
  |---------------------------------|
  | offset(8B) | key_size(8B) | key |
  |---------------------------------|
  """

  defstruct [:entries]

  @type t :: %__MODULE__{entries: Treex.t()}

  @filename "offsets.db"

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

  @spec flush(t(), Path.t()) :: :ok
  def flush(%__MODULE__{entries: tree}, dir) do
    path = Path.join([dir, @filename])

    Treex.stream(tree)
    |> Stream.map(fn {key, offset} ->
      <<offset::unsigned-integer-size(64), <<byte_size(key)::unsigned-integer-size(64)>>,
        key::binary>>
    end)
    |> Stream.into(Fs.stream(path))
    |> Stream.run()
  end

  @spec from_path(Path.t()) :: t()
  def from_path(dir) do
    fun = fn fd, fun, offsets ->
      with <<offset::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
           <<key_size::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
           key <- IO.binread(fd, key_size),
           offsets <- set(offsets, key, offset) do
        fun.(fd, fun, offsets)
      else
        :eof -> offsets
      end
    end

    fd = Path.join([dir, @filename]) |> Fs.open()

    fd
    |> fun.(fun, new())
    |> tap(fn _ -> :ok = File.close(fd) end)
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
