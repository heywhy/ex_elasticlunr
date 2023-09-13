defmodule Box.MemTable do
  alias Box.MemTable.Entry

  defstruct entries: Treex.empty(), size: 0

  @type t :: %__MODULE__{
          entries: Treex.t(),
          size: pos_integer()
        }

  @spec new() :: t()
  def new, do: struct!(__MODULE__)

  @spec length(t()) :: pos_integer()
  def length(%__MODULE__{entries: entries}), do: Treex.size(entries)

  @spec size(t()) :: pos_integer()
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
        size = size + byte_size(key) + byte_size(value) + 16 + 1
        entry = Entry.new(key, value, false, timestamp)

        entries = Treex.insert!(entries, key, entry)

        %{mem_table | entries: entries, size: size}

      {:value, entry} ->
        size =
          case byte_size(value) < byte_size(entry.value) do
            true -> size - byte_size(entry.value) - byte_size(value)
            false -> size + byte_size(value) - byte_size(entry.value)
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
        size = size + byte_size(key) + 16 + 1

        entry = Entry.new(key, nil, true, timestamp)
        entries = Treex.insert!(entries, key, entry)

        %{mem_table | entries: entries, size: size}

      {:value, entry} ->
        size = size - byte_size(entry.value)

        entry = %{entry | value: nil, deleted: true, timestamp: timestamp}
        entries = Treex.update!(entries, key, entry)

        %{mem_table | entries: entries, size: size}
    end
  end
end
