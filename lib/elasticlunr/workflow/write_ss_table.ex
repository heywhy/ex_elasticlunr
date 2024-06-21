defmodule Elasticlunr.Workflow.WriteSSTable do
  use Rop

  alias Elasticlunr.Bloom.Stackable, as: BloomFilter
  alias Elasticlunr.Encoding
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Filename
  alias Elasticlunr.Fs
  alias Elasticlunr.MemTable
  alias Elasticlunr.SSTable.Entry
  alias Elasticlunr.SSTable.Offsets
  alias Elasticlunr.Utils

  @enforce_keys [:entries, :dir, :new_file_num, :tombstone_ttl]
  defstruct [:entries, :dir, :new_file_num, :tombstone_ttl, :max_file_size]

  @type t :: %__MODULE__{
          dir: Path.t(),
          entries: Enum.t(),
          new_file_num: file_num_fn(),
          tombstone_ttl: pos_integer(),
          max_file_size: nil | pos_integer()
        }

  @type file_num_fn :: (-> pos_integer())

  @spec new(MemTable.t() | Enum.t(), Path.t(), file_num_fn(), keyword()) :: t()
  def new(mem_table, dir, new_file_num, opts \\ [])

  def new(%MemTable{} = mem_table, dir, new_file_num, opts) do
    mem_table
    |> MemTable.stream()
    |> Stream.map(&Entry.from/1)
    |> new(dir, new_file_num, opts)
  end

  def new(entries, dir, new_file_num, opts) do
    opts = Keyword.validate!(opts, [:max_file_size, :tombstone_ttl])

    attrs = %{
      dir: dir,
      entries: entries,
      new_file_num: new_file_num,
      max_file_size: opts[:max_file_size],
      tombstone_ttl: opts[:tombstone_ttl]
    }

    struct!(__MODULE__, attrs)
  end

  @spec run(t()) :: {:ok, FileMeta.t()} | {:error, File.posix()}
  def run(%__MODULE__{
        dir: dir,
        entries: entries,
        new_file_num: new_file_num,
        max_file_size: max_file_size,
        tombstone_ttl: tombstone_ttl
      }) do
    now = DateTime.utc_now()

    state = %{
      files: [],
      dir: dir,
      entries: entries,
      new_file_num: new_file_num,
      max_file_size: max_file_size
    }

    entries
    |> Stream.reject(&past_ttl?(&1, tombstone_ttl, now))
    |> Stream.with_index()
    |> Enum.reduce_while(state, fn {entry, index}, state ->
      state
      |> maybe_create_new_file() >>>
        write_entry(entry, index) >>>
        close_file_if_maxed()
      |> case do
        {:ok, state} -> {:cont, state}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> flush_and_close_file()
    |> case do
      %{files: files} -> {:ok, files}
      error -> error
    end
  end

  defp past_ttl?(%{deleted: false}, _ttl, _now), do: false
  defp past_ttl?(%{deleted: true}, nil, _now), do: false

  defp past_ttl?(%{deleted: true, timestamp: ts}, ttl, now) do
    now
    |> DateTime.diff(Utils.to_date_time(ts), :second)
    |> Kernel.>=(ttl)
  end

  defp maybe_create_new_file(%{fd: _fd, file_meta: _} = state), do: {:ok, state}

  defp maybe_create_new_file(%{dir: dir, new_file_num: fun} = state) do
    number = fun.()
    path = Filename.ss_table(dir, number)

    with {:ok, fd} <- Fs.open(path, :write) do
      file_meta = %FileMeta{dir: dir, number: number}

      state
      |> Map.put(:fd, fd)
      |> Map.put(:offset, 0)
      |> Map.put(:file_meta, file_meta)
      |> Map.put(:offsets, Offsets.new())
      |> Map.put(:bloom_filter, BloomFilter.new())
      |> then(&{:ok, &1})
    end
  end

  defp write_entry(
         %{fd: fd, bloom_filter: bf, offset: offset, offsets: offsets} = state,
         entry,
         index
       ) do
    binary = Entry.encode(entry)
    entry_size = Entry.size(entry)
    new_offset = offset + entry_size

    :ok = IO.binwrite(fd, binary)

    bf = BloomFilter.set(bf, entry.key)

    # TODO: allow interval to be configurable
    offsets =
      case rem(index, 128) do
        0 -> Offsets.set(offsets, entry.key, offset)
        _ -> offsets
      end

    %{state | bloom_filter: bf, offset: new_offset, offsets: offsets}
    |> Map.put_new(:smallest_key, entry.key)
    |> Map.put(:largest_key, entry.key)
    |> Map.put(:index_size, new_offset)
    |> Map.put(:last_entry, entry)
    |> then(&{:ok, &1})
  end

  defp close_file_if_maxed(%{offset: size, max_file_size: max} = state) do
    with true <- is_integer(max) and size >= max,
         %{} = state <- flush_and_close_file(state) do
      {:ok, state}
    else
      false -> {:ok, state}
      error -> error
    end
  end

  defp flush_and_close_file(%{fd: _, file_meta: _} = state) do
    flush_offsets(state)
    |> flush_bloom_filter()
    |> write_footer()
    |> close_file()
  end

  defp flush_and_close_file(state), do: state

  defp flush_offsets(%{offset: 0} = state), do: state

  defp flush_offsets(%{fd: fd, offsets: offsets, offset: offset, last_entry: entry} = state) do
    iodata =
      offsets
      |> Offsets.set(entry.key, offset - Entry.size(entry))
      |> Offsets.encode()

    :ok = IO.binwrite(fd, iodata)

    size = IO.iodata_length(iodata)

    state
    |> Map.put(:offset, offset + size)
    |> Map.put(:offsets_size, size)
  end

  defp flush_bloom_filter(%{offset: 0} = state), do: state

  defp flush_bloom_filter(%{fd: fd, offset: offset, bloom_filter: bloom_filter} = state) do
    iodata = BloomFilter.encode(bloom_filter)

    :ok = IO.binwrite(fd, iodata)

    size = IO.iodata_length(iodata)

    state
    |> Map.put(:offset, offset + size)
    |> Map.put(:bloom_filter_size, size)
  end

  defp write_footer(%{offset: 0} = state), do: state

  defp write_footer(
         %{
           fd: fd,
           offset: offset,
           index_size: index_size,
           offsets_size: offsets_size,
           bloom_filter_size: bloom_filter_size
         } = state
       ) do
    binary =
      []
      |> Encoding.put_int64(index_size)
      |> Encoding.put_int64(offsets_size)
      |> Encoding.put_int64(index_size + offsets_size)
      |> Encoding.put_int64(bloom_filter_size)

    footer_size = IO.iodata_length(binary)

    :ok = IO.binwrite(fd, binary)

    %{state | offset: offset + footer_size}
  end

  defp close_file(
         %{
           fd: fd,
           files: files,
           offset: offset,
           file_meta: file_meta,
           largest_key: largest_key,
           smallest_key: smallest_key
         } = state
       ) do
    with :ok <- File.close(fd) do
      file_meta = %{
        file_meta
        | size: offset,
          largest_key: largest_key,
          smallest_key: smallest_key
      }

      state
      |> Map.drop([:fd, :file_meta, :largest_key, :smallest_key])
      |> then(&%{&1 | files: [file_meta | files]})
    end
  end
end
