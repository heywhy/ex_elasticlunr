defmodule Elasticlunr.SSTable do
  @moduledoc """
  """

  alias Elasticlunr.Bloom.Stackable, as: BloomFilter
  alias Elasticlunr.FileMeta
  alias Elasticlunr.MemTable
  alias Elasticlunr.SSTable.Entry
  alias Elasticlunr.SSTable.MergeIterator
  alias Elasticlunr.SSTable.Offsets
  alias Elasticlunr.SSTable.RangeIterator
  alias Elasticlunr.Telemeter
  alias Elasticlunr.Utils
  alias Elasticlunr.Workflow.OpenSSTable
  alias Elasticlunr.Workflow.WriteSSTable

  defstruct [:path, :bloom_filter, :offsets]

  @type t :: %__MODULE__{
          path: Path.t(),
          offsets: Offsets.t(),
          bloom_filter: BloomFilter.t()
        }

  @load_event :load_sstable
  @flush_event :flush_sstable

  @spec new(Path.t(), BloomFilter.t(), Offsets.t()) :: t()
  def new(path, bloom_filter, offsets) do
    attrs = %{
      path: path,
      offsets: offsets,
      bloom_filter: bloom_filter
    }

    struct!(__MODULE__, attrs)
  end

  @spec from_path(FileMeta.t()) :: {:ok, t()} | {:error, File.posix()}
  def from_path(%FileMeta{dir: dir, number: number} = file_meta) do
    metadata = %{
      sstable: number,
      index: index_from_path(dir)
    }

    Telemeter.track(@load_event, metadata, fn ->
      file_meta
      |> OpenSSTable.new()
      |> OpenSSTable.run()
      |> then(&{&1, %{}})
    end)
  end

  @spec flush(MemTable.t(), Path.t(), WriteSSTable.file_num_fn(), nil | keyword()) ::
          {:ok, [FileMeta.t()]} | {:error, File.posix()}
  def flush(%MemTable{} = mem_table, dir, new_file_num, opts \\ []) do
    metadata = %{
      index: index_from_path(dir),
      entries: MemTable.length(mem_table)
    }

    Telemeter.track(@flush_event, metadata, fn ->
      mem_table
      |> WriteSSTable.new(dir, new_file_num, opts)
      |> WriteSSTable.run()
      |> case do
        {:ok, files} = result ->
          files
          |> Enum.reduce(0, &(&1.size + &2))
          |> then(&{result, %{file_size: &1}})

        {:error, reason} = result ->
          {result, %{failure_reason: reason}}
      end
    end)
  end

  @spec merge([FileMeta.t()], Path.t(), WriteSSTable.file_num_fn(), keyword()) ::
          {:ok, [FileMeta.t()]} | {:error, File.posix()}
  def merge(file_metas, dir, new_file_num, opts \\ []) do
    now = DateTime.utc_now()

    file_metas
    |> MergeIterator.new()
    |> Stream.reject(fn
      %Entry{deleted: false} ->
        false

      %Entry{timestamp: ts, deleted: true} ->
        now
        |> DateTime.diff(Utils.to_date_time(ts), :second)
        # TODO: Make tombstone grace period configurable (currently 10 days)
        |> Kernel.>=(864_000)
    end)
    |> WriteSSTable.new(dir, new_file_num, opts)
    |> WriteSSTable.run()
  end

  @spec count(t()) :: pos_integer()
  def count(%__MODULE__{bloom_filter: bf}), do: bf.count

  @spec contains?(t(), binary()) :: boolean()
  def contains?(%__MODULE__{bloom_filter: bf}, key), do: BloomFilter.check?(bf, key)

  @spec get!(t(), binary()) :: Entry.t() | nil | no_return()
  def get!(%__MODULE__{offsets: offsets, path: path} = ss_table, key) do
    with true <- contains?(ss_table, key),
         {_start, _end} = range <- Offsets.get(offsets, key),
         iterator <- RangeIterator.new!(path, range) do
      Enum.find(iterator, &(&1.key == key))
    else
      false -> nil
    end
  end

  defp index_from_path(path), do: Path.basename(path)
end
