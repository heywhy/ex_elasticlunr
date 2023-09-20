defmodule Box.SSTable.MergeIterator do
  alias Box.SSTable.Iterator

  defstruct [:iterators]

  @type t :: %__MODULE__{
          iterators: [Iterator.t()]
        }

  @spec new([Path.t()]) :: t()
  def new(paths) do
    struct!(__MODULE__, iterators: Enum.map(paths, &Iterator.new/1))
  end
end

defimpl Enumerable, for: Box.SSTable.MergeIterator do
  alias Box.SSTable.Entry
  alias Box.SSTable.Iterator
  alias Box.SSTable.MergeIterator

  @impl true
  def member?(%MergeIterator{}, _element), do: throw(:not_implemented)

  @impl true
  def slice(%MergeIterator{}), do: throw(:not_implemented)

  @impl true
  def count(%MergeIterator{}), do: throw(:not_implemented)

  @impl true
  def reduce(%MergeIterator{}, {:halt, acc}, _fun), do: {:halted, acc}
  def reduce(%MergeIterator{iterators: []}, {:cont, acc}, _fun), do: {:done, acc}

  def reduce(%MergeIterator{iterators: iterators} = mi, {:cont, acc}, fun) do
    entries =
      iterators
      |> Enum.map(&Iterator.current(&1))
      |> Enum.reject(&is_nil(elem(&1, 0)))
      |> Enum.sort_by(fn {entry, _iterator} -> {entry.key, entry.timestamp} end)

    with [_ | _rest] <- entries,
         {entry, iterators} <- next_entry(entries) do
      reduce(%{mi | iterators: iterators}, fun.(entry, acc), fun)
    else
      [] -> reduce(%{mi | iterators: []}, {:cont, acc}, fun)
    end
  end

  defp next_entry([{%Entry{key: key}, _}, {%Entry{key: key}, _} | _rest] = entries) do
    {duplicates, rest} =
      Enum.split_with(entries, fn {entry, _iterator} -> entry.key == key end)

    [{entry, _iterator} | _rest] =
      Enum.sort_by(duplicates, fn {entry, _} -> entry.timestamp end, :desc)

    iterators =
      duplicates
      |> Enum.map(fn {_entry, iterator} ->
        {_e, _i} = Iterator.next(iterator)
      end)
      |> Enum.concat(rest)
      |> Enum.map(&elem(&1, 1))

    {entry, iterators}
  end

  defp next_entry([{%Entry{} = entry, iterator} | rest]) do
    {_, iterator} = Iterator.next(iterator)

    {entry, [iterator] ++ Enum.map(rest, &elem(&1, 1))}
  end
end
