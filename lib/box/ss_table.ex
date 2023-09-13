defmodule Box.SSTable do
  alias Box.MemTable
  alias Box.MemTable.Entry, as: MEntry
  alias Box.SSTable.Entry
  alias Box.SSTable.Iterator

  defstruct [:path, :offsets, :entries]

  @type t :: %__MODULE__{
          path: Path.t(),
          entries: Treex.t(),
          offsets: %{binary() => pos_integer()}
        }

  @ext "seg"

  @spec new(Path.t()) :: t()
  def new(path) do
    struct!(__MODULE__, path: path, entries: Treex.empty())
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
  def flush(%MemTable{} = mem_table, dir) do
    path = create_file(dir)
    length = MemTable.length(mem_table)

    file =
      path
      |> File.stream!([:append])
      # Store entries count as the first byte in the file
      |> then(&Enum.into([<<length::unsigned-integer>>], &1))

    :ok =
      mem_table
      |> MemTable.stream()
      |> Stream.map(&to_binary(&1))
      |> Stream.into(file)
      |> Stream.run()

    path
  end

  @spec count(t()) :: pos_integer()
  def count(%__MODULE__{path: path}) do
    with iter <- Iterator.new(path),
         count <- Enum.count(iter),
         :ok <- Iterator.destroy(iter) do
      count
    end
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
    case Treex.lookup(entries, key) do
      :none -> nil
      {:value, entry} -> entry
    end
  end

  defp create_file(dir) do
    dir = Path.join(dir, "_segments")
    now = System.os_time(:microsecond)

    unless File.dir?(dir) do
      :ok = File.mkdir!(dir)
    end

    Path.join(dir, "#{now}.seg")
  end

  defp set(%__MODULE__{entries: entries} = ss_table, key, value, timestamp) do
    entry = Entry.new(key, value, false, timestamp)
    entries = Treex.insert!(entries, key, entry)

    %{ss_table | entries: entries}
  end

  defp remove(%__MODULE__{entries: entries} = ss_table, key, timestamp) do
    entry = Entry.new(key, nil, true, timestamp)
    entries = Treex.insert!(entries, key, entry)

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
