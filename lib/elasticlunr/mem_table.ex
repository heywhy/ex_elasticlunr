defmodule Elasticlunr.MemTable do
  alias Elasticlunr.MemTable.Entry

  defstruct entries: Treex.empty(), size: 0

  @type t :: %__MODULE__{
          entries: Treex.t(),
          size: non_neg_integer()
        }

  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{entries: entries}), do: Treex.size(entries)

  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @spec stream(t()) :: Enumerable.t()
  def stream(%__MODULE__{entries: entries}) do
    entries
    |> Treex.stream()
    |> Stream.map(&elem(&1, 1))
  end

  @spec get(t(), binary()) :: Entry.t() | nil
  def get(%__MODULE__{entries: entries}, key) do
    case Treex.lookup(entries, key) do
      :none -> nil
      {:value, entry} -> entry
    end
  end

  @spec set(t(), binary(), binary(), pos_integer()) :: t()
  def set(%__MODULE__{entries: entries, size: size} = mem_table, key, value, timestamp) do
    case Treex.lookup(entries, key) do
      :none ->
        size = size + IO.iodata_length(key) + IO.iodata_length(value) + 16 + 1
        entry = %Entry{key: key, value: value, deleted: false, timestamp: timestamp}

        entries = Treex.insert!(entries, key, entry)

        %{mem_table | entries: entries, size: size}

      {:value, entry} ->
        size =
          case IO.iodata_length(value) < IO.iodata_length(entry.value) do
            true -> size - IO.iodata_length(entry.value) - IO.iodata_length(value)
            false -> size + IO.iodata_length(value) - IO.iodata_length(entry.value)
          end

        entry = %{entry | value: value, deleted: false, timestamp: timestamp}
        entries = Treex.update!(entries, key, entry)

        %{mem_table | entries: entries, size: size}
    end
  end

  @spec remove(t(), binary(), pos_integer()) :: t()
  def remove(%__MODULE__{entries: entries, size: size} = mem_table, key, timestamp) do
    case Treex.lookup(entries, key) do
      :none ->
        size = size + IO.iodata_length(key) + 16 + 1

        entry = %Entry{key: key, value: nil, deleted: true, timestamp: timestamp}
        entries = Treex.insert!(entries, key, entry)

        %{mem_table | entries: entries, size: size}

      {:value, entry} ->
        size = size - IO.iodata_length(entry.value)

        entry = %{entry | value: nil, deleted: true, timestamp: timestamp}
        entries = Treex.update!(entries, key, entry)

        %{mem_table | entries: entries, size: size}
    end
  end
end
