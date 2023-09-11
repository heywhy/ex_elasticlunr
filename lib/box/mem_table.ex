defmodule Box.MemTable do
  alias Box.MemTable.Entry

  @enforce_keys [:entries]
  defstruct [:entries, size: 0]

  @type t :: %__MODULE__{
          size: pos_integer(),
          entries: :gb_trees.tree(binary(), Entry.t())
        }

  @spec new() :: t()
  def new do
    struct!(__MODULE__, entries: :gb_trees.empty())
  end

  @spec length(t()) :: pos_integer()
  def length(%__MODULE__{entries: entries}), do: :gb_trees.size(entries)

  @spec size(t()) :: pos_integer()
  def size(%__MODULE__{size: size}), do: size

  @spec get(t(), binary()) :: Entry.t() | nil
  def get(%__MODULE__{entries: entries}, key) do
    case :gb_trees.lookup(key, entries) do
      :none -> nil
      {:value, entry} -> entry
    end
  end

  @spec set(t(), binary(), binary(), pos_integer()) :: t()
  def set(%__MODULE__{entries: entries, size: size} = mem_table, key, value, timestamp) do
    case :gb_trees.lookup(key, entries) do
      :none ->
        size = size + byte_size(key) + byte_size(value) + 16 + 1
        entry = Entry.new(key, value, false, timestamp)

        entries = :gb_trees.insert(key, entry, entries)

        %{mem_table | entries: entries, size: size}

      {:value, entry} ->
        size =
          case byte_size(value) < byte_size(entry.value) do
            true -> size - byte_size(entry.value) - byte_size(value)
            false -> size + byte_size(value) - byte_size(entry.value)
          end

        entry = %{entry | value: value, deleted: false, timestamp: timestamp}
        entries = :gb_trees.update(key, entry, entries)

        %{mem_table | entries: entries, size: size}
    end
  end

  @spec remove(t(), binary(), pos_integer()) :: t()
  def remove(%__MODULE__{entries: entries, size: size} = mem_table, key, timestamp) do
    case :gb_trees.lookup(key, entries) do
      :none ->
        size = size + byte_size(key) + 16 + 1

        entry = Entry.new(key, nil, true, timestamp)
        entries = :gb_trees.insert(key, entry, entries)

        %{mem_table | entries: entries, size: size}

      {:value, entry} ->
        size = size - byte_size(entry.value)

        entry = %{entry | value: nil, deleted: true, timestamp: timestamp}
        entries = :gb_trees.update(key, entry, entries)

        %{mem_table | entries: entries, size: size}
    end
  end
end
