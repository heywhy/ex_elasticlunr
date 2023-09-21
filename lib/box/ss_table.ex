defmodule Box.SSTable do
  alias Box.Bloom.Stackable, as: StackableBloom
  alias Box.Fs
  alias Box.MemTable
  alias Box.SSTable.Entry
  alias Box.SSTable.Iterator
  alias Box.SSTable.MergeIterator
  alias Box.SSTable.Shared
  alias Box.Utils

  defstruct [:path, :bloom_filter, :offsets, :entries]

  @type t :: %__MODULE__{
          path: Path.t(),
          entries: Treex.t(),
          bloom_filter: StackableBloom.t(),
          offsets: %{binary() => pos_integer()}
        }

  @lockfile "_.lock"

  @spec from_path(Path.t()) :: t() | no_return()
  def from_path(path) do
    with path <- Path.absname(path) |> Path.expand(),
         bloom_filter <- StackableBloom.from_path(path),
         %Iterator{} = iterator <- Iterator.new(path),
         ss_table <- new(path, bloom_filter) do
      Enum.reduce(iterator, ss_table, fn %Entry{} = entry, ss_table ->
        case entry.deleted do
          true -> remove(ss_table, entry.key, entry.timestamp)
          false -> set(ss_table, entry.key, entry.value, entry.timestamp)
        end
      end)
    end
  end

  @spec flush(MemTable.t(), Path.t()) :: Path.t() | no_return()
  def flush(%MemTable{} = mem_table, dir) do
    path = new_dir(dir)

    :ok =
      mem_table
      |> MemTable.stream()
      |> Stream.map(&Entry.from/1)
      |> write_to_disk(path)

    path
  end

  @spec merge(Path.t()) :: Path.t() | no_return()
  def merge(dir) do
    paths = list(dir)
    path = new_dir(dir)

    :ok =
      paths
      |> MergeIterator.new()
      |> Stream.reject(& &1.deleted)
      |> write_to_disk(path)

    # Delete all merged sstables
    :ok = Enum.each(paths, &File.rm_rf!/1)

    path
  end

  @spec count(t()) :: pos_integer()
  def count(%__MODULE__{bloom_filter: bf}), do: bf.count

  @spec contains?(t(), binary()) :: boolean()
  def contains?(%__MODULE__{bloom_filter: bf}, key), do: StackableBloom.check(bf, key)

  @spec lockfile?(Path.t()) :: boolean()
  def lockfile?(path) do
    path
    |> String.match?(~r/_segments\/[\d+]+\//i)
    |> Kernel.and(Path.basename(path) == @lockfile)
  end

  @spec list(Path.t()) :: [Path.t()]
  def list(dir) do
    dir
    |> Path.join("_segments")
    |> then(&Path.wildcard("#{&1}/*"))
  end

  @spec get(t(), binary()) :: Entry.t() | nil
  def get(%__MODULE__{entries: entries}, key) do
    case Treex.lookup(entries, key) do
      :none -> nil
      {:value, entry} -> entry
    end
  end

  defp new(path, bloom_filter) do
    attrs = %{
      path: path,
      entries: Treex.empty(),
      bloom_filter: bloom_filter
    }

    struct!(__MODULE__, attrs)
  end

  defp new_dir(dir) do
    now = Utils.now()
    path = Path.join([dir, "_segments", to_string(now)]) |> Path.expand()

    with false <- File.dir?(path),
         :ok <- File.mkdir_p!(path) do
      path
    else
      true -> path
    end
  end

  defp write_to_disk(entries, path) do
    file = Shared.segment_file(path)

    entries
    |> Stream.map(&to_binary/1)
    |> Stream.into(Fs.stream(file))
    # TODO: allow chance to be configured by user just like cassandra
    |> Enum.reduce(StackableBloom.new(), &write_to_bf(&2, &1))
    |> StackableBloom.flush(path)

    :ok = gen_lockfile(path)
  end

  defp write_to_bf(bloom_filter, entry) do
    case entry do
      <<key_size::unsigned-integer-size(64), 1, key::binary-size(key_size), _rest::binary>> ->
        StackableBloom.set(bloom_filter, key)

      <<key_size::unsigned-integer-size(64), 0, _value_size::unsigned-integer-size(64),
        key::binary-size(key_size), _rest::binary>> ->
        StackableBloom.set(bloom_filter, key)
    end
  end

  defp gen_lockfile(path), do: Path.join(path, @lockfile) |> File.touch!()

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

  defp to_binary(%Entry{deleted: true, key: key, timestamp: timestamp}) do
    key_size = byte_size(key)
    key_size_data = <<key_size::unsigned-integer-size(64)>>

    timestamp_data = <<timestamp::big-unsigned-integer-size(64)>>

    sizes_data = <<key_size_data::binary, 1>>

    <<sizes_data::binary, key::binary, timestamp_data::binary>>
  end

  defp to_binary(%Entry{deleted: false, key: key, value: value, timestamp: timestamp}) do
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
