defmodule Elasticlunr.SSTable do
  alias Elasticlunr.Bloom.Stackable, as: BloomFilter
  alias Elasticlunr.Fs
  alias Elasticlunr.MemTable
  alias Elasticlunr.SSTable.Entry
  alias Elasticlunr.SSTable.MergeIterator
  alias Elasticlunr.SSTable.Offsets
  alias Elasticlunr.SSTable.RangeIterator
  alias Elasticlunr.SSTable.Shared
  alias Elasticlunr.Telemeter
  alias Elasticlunr.Utils

  defstruct [:path, :bloom_filter, :offsets]

  @type t :: %__MODULE__{
          path: Path.t(),
          offsets: Offsets.t(),
          bloom_filter: BloomFilter.t()
        }

  @lockfile "_.lock"
  @load_event :load_sstable
  @flush_event :flush_sstable

  @spec from_path(Path.t()) :: t() | no_return()
  def from_path(path) do
    metadata = %{
      index: index_from_path(path),
      sstable: Path.basename(path)
    }

    Telemeter.track(@load_event, metadata, fn ->
      with path <- Path.absname(path) |> Path.expand(),
           offsets <- Offsets.from_path(path),
           bloom_filter <- BloomFilter.from_path(path),
           result <- new(path, bloom_filter, offsets) do
        {result, %{entries: BloomFilter.count(bloom_filter)}}
      end
    end)
  end

  @spec flush(MemTable.t(), Path.t()) :: Path.t() | no_return()
  def flush(%MemTable{} = mem_table, dir) do
    path = new_dir(dir)

    metadata = %{
      index: index_from_path(path),
      sstable: Path.basename(path),
      entries: MemTable.length(mem_table)
    }

    Telemeter.track(@flush_event, metadata, fn ->
      :ok =
        mem_table
        |> MemTable.stream()
        |> Stream.map(&Entry.from/1)
        |> write_to_disk(path)

      path
    end)
  end

  @spec merge([Path.t()], Path.t()) :: Path.t() | no_return()
  def merge(paths, dir) do
    path = new_dir(dir)

    :ok =
      paths
      |> MergeIterator.new()
      |> Stream.reject(fn %Entry{timestamp: ts} ->
        DateTime.utc_now()
        |> DateTime.diff(Utils.to_date_time(ts), :second)
        # TODO: Make tombstone grace period configurable (currently 10 days)
        |> Kernel.>=(864_000)
      end)
      |> write_to_disk(path)

    # Delete all merged sstables
    :ok = Enum.each(paths, &File.rm_rf!/1)

    path
  end

  @spec count(t()) :: pos_integer()
  def count(%__MODULE__{bloom_filter: bf}), do: bf.count

  @spec contains?(t(), binary()) :: boolean()
  def contains?(%__MODULE__{bloom_filter: bf}, key), do: BloomFilter.check?(bf, key)

  @spec size(Path.t()) :: non_neg_integer()
  def size(dir) do
    dir
    |> Shared.segment_file()
    |> File.stat!()
    |> then(& &1.size)
  end

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
  def get(%__MODULE__{offsets: offsets, path: path} = ss_table, key) do
    with true <- contains?(ss_table, key),
         {_start, _end} = range <- Offsets.get(offsets, key),
         iterator <- RangeIterator.new(path, range) do
      Enum.find(iterator, &(&1.key == key))
    else
      false -> nil
    end
  end

  defp new(path, bloom_filter, offsets) do
    attrs = %{
      path: path,
      offsets: offsets,
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
    # TODO: allow chance to be configured by user just like cassandra
    acc = {BloomFilter.new(), Offsets.new(), nil, 0}

    {bloom_filter, offsets, entry, offset} =
      entries
      |> Stream.map(&Entry.to_binary/1)
      |> Stream.into(Fs.stream(file))
      |> Stream.with_index()
      |> Enum.reduce(acc, fn {binary, index}, {bloom_filter, offsets, _last_entry, offset} ->
        entry = Entry.from(binary)
        bloom_filter = BloomFilter.set(bloom_filter, entry.key)

        # TODO: allow interval to be configurable
        offsets =
          case rem(index, 128) do
            0 -> Offsets.set(offsets, entry.key, offset)
            _ -> offsets
          end

        {bloom_filter, offsets, entry, offset + Entry.size(entry)}
      end)

    # Add the last entry in case the interval in the reduction function does not capture it
    offsets = Offsets.set(offsets, entry.key, offset - Entry.size(entry))

    :ok = Offsets.flush(offsets, path)
    :ok = BloomFilter.flush(bloom_filter, path)
    :ok = gen_lockfile(path)
  end

  defp gen_lockfile(path), do: Path.join(path, @lockfile) |> File.touch!()

  defp index_from_path(path) do
    Path.join([path, "..", ".."])
    |> Path.expand()
    |> Path.basename()
  end
end
