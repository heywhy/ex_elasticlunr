defmodule Elasticlunr.Workflow.OpenSSTable do
  use Rop

  alias Elasticlunr.Bloom.Stackable, as: BloomFilter
  alias Elasticlunr.Encoding
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Filename
  alias Elasticlunr.Fs
  alias Elasticlunr.SSTable
  alias Elasticlunr.SSTable.Offsets

  @enforce_keys [:path, :size]
  defstruct [:path, :size]

  @type t :: %__MODULE__{path: Path.t()}

  @spec new(FileMeta.t()) :: t()
  def new(%FileMeta{dir: dir, number: number, size: size}) do
    dir
    |> Filename.ss_table(number)
    |> then(&struct!(__MODULE__, path: &1, size: size))
  end

  @spec run(t()) :: {:ok, SSTable.t()} | {:error, File.posix()}
  def run(%__MODULE__{path: path, size: size}) do
    open_file(%{path: path, size: size}) >>>
      read_footer() >>>
      read_bloom_filter() >>>
      read_offsets() >>>
      close_file()
  end

  defp open_file(%{path: path} = state) do
    with {:ok, fd} <- Fs.open(path) do
      {:ok, Map.put(state, :fd, fd)}
    end
  end

  defp read_footer(%{fd: fd, size: size} = state) do
    # 32 here is the bytes used to store the footer
    position = size - 32

    with {:ok, ^position} <- :file.position(fd, position) do
      offsets_offset = Encoding.get_int64!(fd)
      offsets_size = Encoding.get_int64!(fd)
      bloom_filter_offset = Encoding.get_int64!(fd)
      bloom_filter_size = Encoding.get_int64!(fd)

      new_state = %{
        offsets_size: offsets_size,
        offsets_offset: offsets_offset,
        bloom_filter_size: bloom_filter_size,
        bloom_filter_offset: bloom_filter_offset
      }

      {:ok, Map.merge(state, new_state)}
    end
  end

  defp read_offsets(%{fd: fd, offsets_size: size, offsets_offset: offset} = state) do
    with {:ok, ^offset} <- :file.position(fd, offset) do
      binary = IO.binread(fd, size)
      offsets = Offsets.decode!(binary)

      {:ok, Map.put(state, :offsets, offsets)}
    end
  end

  defp read_bloom_filter(%{fd: fd, bloom_filter_size: size, bloom_filter_offset: offset} = state) do
    with {:ok, ^offset} <- :file.position(fd, offset) do
      binary = IO.binread(fd, size)
      bloom_filter = BloomFilter.decode!(binary)

      {:ok, Map.put(state, :bloom_filter, bloom_filter)}
    end
  end

  defp close_file(%{fd: fd, path: path, offsets: offsets, bloom_filter: bloom_filter}) do
    with :ok <- File.close(fd) do
      {:ok, %SSTable{path: path, bloom_filter: bloom_filter, offsets: offsets}}
    end
  end
end
