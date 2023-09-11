defmodule Box.SSTable do
  alias Box.MemTable
  alias Box.MemTable.Entry, as: MEntry
  alias Box.SSTable.Entry
  alias Box.SSTable.Iterator

  defstruct [:path, :offsets, :entries]

  @type t :: %__MODULE__{
          path: Path.t(),
          offsets: %{binary() => pos_integer()},
          entries: :gb_trees.tree(binary(), Entry.t())
        }

  @ext "seg"

  @spec new(Path.t()) :: t()
  def new(path) do
    struct!(__MODULE__, path: path, entries: :gb_trees.empty())
  end

  @spec from_path(Path.t()) :: t() | no_return()
  def from_path(path) do
    Iterator.new(path)
    |> Enum.reduce(new(path), fn %Entry{} = entry, ss_table ->
      case entry.deleted do
        true -> remove(ss_table, entry.key, entry.timestamp)
        false -> set(ss_table, entry.key, entry.value, entry.timestamp)
      end
    end)
  end

  @spec flush(MemTable.t(), Path.t()) :: Path.t() | no_return()
  def flush(%MemTable{entries: entries}, dir) do
    now = System.os_time(:microsecond)
    dir = Path.join(dir, "_segments")
    path = Path.join(dir, "#{now}.seg")

    unless File.dir?(dir) do
      :ok = File.mkdir!(dir)
    end

    :ok =
      :gb_trees.to_list(entries)
      |> Stream.map(&elem(&1, 1))
      |> Stream.map(&to_binary(&1))
      |> Stream.into(File.stream!(path, [:append]))
      |> Stream.run()

    path
  end

  @spec is?(Path.t()) :: boolean()
  def is?(path), do: Path.extname(path) == ".#{@ext}"

  @spec list(Path.t()) :: [Path.t()]
  def list(dir) do
    dir
    |> Path.join("_segments")
    |> then(&Path.wildcard("#{&1}/*.#{@ext}"))
  end

  @spec get(t(), binary()) :: Entry.t() | nil
  def get(%__MODULE__{entries: entries}, key) do
    case :gb_trees.lookup(key, entries) do
      :none -> nil
      {:value, entry} -> entry
    end
  end

  defp set(%__MODULE__{entries: entries} = ss_table, key, value, timestamp) do
    entry = Entry.new(key, value, false, timestamp)
    entries = :gb_trees.insert(key, entry, entries)

    %{ss_table | entries: entries}
  end

  defp remove(%__MODULE__{entries: entries} = ss_table, key, timestamp) do
    entry = Entry.new(key, nil, true, timestamp)
    entries = :gb_trees.insert(key, entry, entries)

    %{ss_table | entries: entries}
  end

  defp to_binary(%MEntry{deleted: true, key: key, timestamp: timestamp}) do
    key_size = byte_size(key)
    key_size_data = <<key_size::unsigned-integer-size(64)>>

    deleted_data = <<1::unsigned-integer>>

    timestamp_data = <<timestamp::big-unsigned-integer-size(64)>>

    sizes_data = <<key_size_data::binary, deleted_data::binary>>

    <<sizes_data::binary, key::binary, timestamp_data::binary>>
  end

  defp to_binary(%MEntry{deleted: false, key: key, value: value, timestamp: timestamp}) do
    key_size = byte_size(key)
    key_size_data = <<key_size::unsigned-integer-size(64)>>

    deleted_data = <<0::unsigned-integer>>

    timestamp_data = <<timestamp::big-unsigned-integer-size(64)>>

    value_size = byte_size(value)
    value_size_data = <<value_size::unsigned-integer-size(64)>>

    sizes_data = <<key_size_data::binary, deleted_data::binary, value_size_data::binary>>

    kv_data = <<key::binary, value::binary>>

    <<sizes_data::binary, kv_data::binary, timestamp_data::binary>>
  end
end
