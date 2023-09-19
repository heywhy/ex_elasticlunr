defmodule Box.SSTable do
  alias Box.MemTable
  alias Box.MemTable.Entry, as: MEntry
  alias Box.SSTable.Entry
  alias Box.SSTable.Iterator

  defstruct [:path, :bloom_filter, :offsets, :entries, :length]

  @type t :: %__MODULE__{
          path: Path.t(),
          bloom_filter: reference(),
          entries: Treex.t(),
          length: pos_integer(),
          offsets: %{binary() => pos_integer()}
        }

  @ext "seg"
  @bf_ext "bf"

  @spec from_path(Path.t()) :: t() | no_return()
  def from_path(path) do
    with path <- Path.absname(path) |> Path.expand(),
         bloom_filter <- load_bloom_filter(path),
         %Iterator{count: count} = iterator <- Iterator.new(path),
         ss_table <- new(path, count, bloom_filter) do
      Enum.reduce(iterator, ss_table, fn %Entry{} = entry, ss_table ->
        case entry.deleted do
          true -> remove(ss_table, entry.key, entry.timestamp)
          false -> set(ss_table, entry.key, entry.value, entry.timestamp)
        end
      end)
    end
  end

  @spec flush(MemTable.t(), Path.t()) :: Path.t() | no_return()
  def flush(%MemTable{entries: entries} = mem_table, dir) do
    path = create_file(dir)
    length = MemTable.length(mem_table)
    {upper_bound, _value} = Treex.largest!(entries)
    {lower_bound, _value} = Treex.smallest!(entries)
    # TODO: allow chance to be configured by user just like cassandra
    {:ok, bloom_filter} = :bloom.new_optimal(length, 0.01)

    # Store metadata in the first 3 bytes in the file
    metadata = [
      <<length::unsigned-integer-size(64)>>,
      <<byte_size(lower_bound)::unsigned-integer>>,
      <<byte_size(upper_bound)::unsigned-integer>>,
      lower_bound,
      upper_bound
    ]

    file =
      path
      |> File.stream!([:append])
      |> then(&Enum.into(metadata, &1))

    :ok =
      mem_table
      |> MemTable.stream()
      |> Stream.map(&to_binary/1)
      |> Stream.into(file)
      |> Stream.each(fn
        <<key_size::unsigned-integer-size(64), 1, key::binary-size(key_size), _rest::binary>> ->
          :ok = :bloom.set(bloom_filter, key)

        <<key_size::unsigned-integer-size(64), 0, _value_size::unsigned-integer-size(64),
          key::binary-size(key_size), _rest::binary>> ->
          :ok = :bloom.set(bloom_filter, key)
      end)
      |> Stream.run()

    :ok = save_bloom_filter(bloom_filter, path)

    path
  end

  @spec length(t()) :: pos_integer()
  def length(%__MODULE__{length: length}), do: length

  @spec contains?(t(), binary()) :: boolean()
  def contains?(%__MODULE__{bloom_filter: bf}, key), do: :bloom.check(bf, key)

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

  defp new(path, length, bloom_filter) do
    attrs = %{
      path: path,
      length: length,
      entries: Treex.empty(),
      bloom_filter: bloom_filter
    }

    struct!(__MODULE__, attrs)
  end

  defp create_file(dir) do
    dir = Path.join(dir, "_segments")
    now = System.os_time(:microsecond)

    unless File.dir?(dir) do
      :ok = File.mkdir!(dir)
    end

    Path.join(dir, "#{now}.seg")
  end

  defp save_bloom_filter(bloom_filter, path) do
    with bf_path <- "#{path}.#{@bf_ext}",
         {:ok, bin} <- :bloom.serialize(bloom_filter) do
      File.write!(bf_path, bin, [:binary, :compressed])
    end
  end

  defp load_bloom_filter(path) do
    with path <- "#{path}.#{@bf_ext}",
         fd <- File.open!(path, [:read, :binary, :compressed]),
         bin <- IO.binread(fd, :eof),
         :ok <- File.close(fd),
         {:ok, ref} <- :bloom.deserialize(bin) do
      ref
    end
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

    timestamp_data = <<timestamp::big-unsigned-integer-size(64)>>

    sizes_data = <<key_size_data::binary, 1>>

    <<sizes_data::binary, key::binary, timestamp_data::binary>>
  end

  defp to_binary(%MEntry{deleted: false, key: key, value: value, timestamp: timestamp}) do
    key_size = byte_size(key)
    key_size_data = <<key_size::unsigned-integer-size(64)>>

    timestamp_data = <<timestamp::big-unsigned-integer-size(64)>>

    value_size = byte_size(value)
    value_size_data = <<value_size::unsigned-integer-size(64)>>

    sizes_data = <<key_size_data::binary, 0, value_size_data::binary>>

    kv_data = <<key::binary, value::binary>>

    <<sizes_data::binary, kv_data::binary, timestamp_data::binary>>
  end
end
