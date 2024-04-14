defmodule Elasticlunr.Workflow.WriteSSTable do
  use Rop

  alias Elasticlunr.Bloom.Stackable, as: BloomFilter
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Filename
  alias Elasticlunr.Fs
  alias Elasticlunr.MemTable
  alias Elasticlunr.SSTable.Entry
  alias Elasticlunr.SSTable.Offsets

  @enforce_keys [:entries, :file_meta]
  defstruct [:entries, :file_meta, :bloom_filter, offsets: Offsets.new()]

  @type t :: %__MODULE__{
          entries: Enum.t(),
          offsets: Offsets.t(),
          bloom_filter: BloomFilter.t()
        }

  @spec new(MemTable.t() | Enum.t(), FileMeta.t()) :: t()
  def new(%MemTable{} = mem_table, %FileMeta{} = file_meta) do
    mem_table
    |> MemTable.stream()
    |> Stream.map(&Entry.from/1)
    |> new(file_meta)
  end

  def new(entries, file_meta) do
    attrs = %{
      entries: entries,
      file_meta: file_meta,
      bloom_filter: BloomFilter.new()
    }

    struct!(__MODULE__, attrs)
  end

  @spec run(t()) :: {:ok, FileMeta.t()} | {:error, File.posix()}
  def run(%__MODULE__{
        entries: entries,
        file_meta: file_meta,
        offsets: offsets,
        bloom_filter: bloom_filter
      }) do
    %{
      offset: 0,
      last_entry: nil,
      largest_key: nil,
      smallest_key: nil,
      entries: entries,
      offsets: offsets,
      file_meta: file_meta,
      bloom_filter: bloom_filter
    }
    |> open_file() >>>
      flush_entries() >>>
      flush_offsets() >>>
      flush_bloom_filter() >>>
      write_footer() >>>
      close_file()
  end

  defp open_file(%{file_meta: %FileMeta{dir: dir, number: number}} = state) do
    dir
    |> Filename.ss_table(number)
    |> Fs.open(:write)
    |> case do
      {:ok, fd} -> {:ok, Map.put(state, :fd, fd)}
      error -> error
    end
  end

  defp flush_entries(%{fd: fd, entries: entries} = state) do
    state = Map.put(state, :index_size, 0)

    entries
    |> Stream.with_index()
    |> Enum.reduce_while({:ok, state}, fn {entry, index}, acc ->
      %{offset: offset, offsets: offsets, bloom_filter: bloom_filter, smallest_key: smallest_key} =
        ok(acc)

      entry_size = Entry.size(entry)
      binary = Entry.to_binary(entry)
      new_offset = offset + entry_size

      case IO.binwrite(fd, binary) do
        :ok ->
          bloom_filter = BloomFilter.set(bloom_filter, entry.key)

          # TODO: allow interval to be configurable
          offsets =
            case rem(index, 128) do
              0 -> Offsets.set(offsets, entry.key, offset)
              _ -> offsets
            end

          new_state = %{
            state
            | offsets: offsets,
              bloom_filter: bloom_filter,
              last_entry: entry,
              offset: new_offset,
              index_size: new_offset,
              largest_key: entry.key,
              smallest_key: smallest_key || entry.key
          }

          {:cont, {:ok, new_state}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp flush_offsets(%{last_entry: nil} = state), do: {:ok, state}

  defp flush_offsets(%{fd: fd, offsets: offsets, offset: offset, last_entry: entry} = state) do
    iodata =
      offsets
      |> Offsets.set(entry.key, offset - Entry.size(entry))
      |> Offsets.encode()

    size = IO.iodata_length(iodata)

    case IO.binwrite(fd, iodata) do
      :ok ->
        state
        |> Map.put(:offset, offset + size)
        |> Map.put(:offsets_size, size)
        |> then(&{:ok, &1})

      error ->
        error
    end
  end

  defp flush_bloom_filter(%{fd: fd, offset: offset, bloom_filter: bloom_filter} = state) do
    iodata = BloomFilter.encode(bloom_filter)
    size = IO.iodata_length(iodata)

    case IO.binwrite(fd, iodata) do
      :ok ->
        state
        |> Map.put(:offset, offset + size)
        |> Map.put(:bloom_filter_size, size)
        |> then(&{:ok, &1})

      error ->
        error
    end
  end

  defp write_footer(
         %{
           fd: fd,
           offset: offset,
           index_size: index_size,
           offsets_size: offsets_size,
           bloom_filter_size: bloom_filter_size
         } = state
       ) do
    binary = <<
      index_size::unsigned-integer-size(64),
      offsets_size::unsigned-integer-size(64),
      index_size + offsets_size::unsigned-integer-size(64),
      bloom_filter_size::unsigned-integer-size(64)
    >>

    footer_size = byte_size(binary)

    case IO.binwrite(fd, binary) do
      :ok -> {:ok, %{state | offset: offset + footer_size}}
      error -> error
    end
  end

  defp close_file(%{
         fd: fd,
         offset: offset,
         file_meta: file_meta,
         largest_key: largest_key,
         smallest_key: smallest_key
       }) do
    with :ok <- File.close(fd) do
      {:ok, %{file_meta | size: offset, largest_key: largest_key, smallest_key: smallest_key}}
    end
  end
end
