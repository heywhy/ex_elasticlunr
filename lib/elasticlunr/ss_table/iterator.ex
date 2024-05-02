defmodule Elasticlunr.SSTable.Iterator do
  alias Elasticlunr.Encoding
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Filename
  alias Elasticlunr.Fs
  alias Elasticlunr.SSTable.Entry

  defstruct [:fd, :path, :index_size, offset: 0]

  @type t :: %__MODULE__{
          path: Path.t(),
          fd: File.io_device(),
          offset: pos_integer(),
          index_size: pos_integer()
        }

  @spec new!(FileMeta.t()) :: t() | no_return()
  def new!(%FileMeta{dir: dir, size: size, number: number}) do
    path = Filename.ss_table(dir, number)
    fd = Fs.open!(path)
    index_size = read_index_size!(fd, size)

    attrs = %{
      fd: fd,
      path: path,
      index_size: index_size
    }

    struct!(__MODULE__, attrs)
  end

  @spec eof?(t()) :: boolean()
  def eof?(%__MODULE__{offset: offset, index_size: index_size}), do: offset == index_size

  @spec next(t()) :: {Entry.t(), t()} | no_return()
  def next(%__MODULE__{offset: offset} = iterator) when is_integer(offset) do
    {entry, new_offset, iterator} = read(iterator)

    iterator = %{iterator | offset: new_offset}

    case eof?(iterator) do
      true ->
        :ok = File.close(iterator.fd)
        {entry, iterator}

      false ->
        {entry, iterator}
    end
  end

  @spec current(t()) :: {Entry.t(), t()}
  def current(%__MODULE__{} = iterator) do
    {entry, _new_offset, iterator} = read(iterator)

    {entry, iterator}
  end

  defp read(%__MODULE__{fd: fd, offset: offset} = iterator) do
    with {:ok, ^offset} <- :file.position(fd, offset),
         %Entry{} = entry <- Entry.read!(fd) do
      new_offset =
        case IO.binread(fd, 1) do
          :eof -> :eof
          _ -> offset + Entry.size(entry)
        end

      {entry, new_offset, iterator}
    end
  end

  defp read_index_size!(fd, size) do
    position = size - 32

    {:ok, ^position} = :file.position(fd, position)

    _oo = Encoding.get_int64!(fd)
    offsets_size = Encoding.get_int64!(fd)
    _bfo = Encoding.get_int64!(fd)
    bloom_filter_size = Encoding.get_int64!(fd)

    position - bloom_filter_size - offsets_size
  end
end

defimpl Enumerable, for: Elasticlunr.SSTable.Iterator do
  alias Elasticlunr.SSTable.Iterator

  import Iterator, only: [next: 1]

  # coveralls-ignore-start
  @impl true
  def member?(%Iterator{}, _element), do: throw(:not_implemented)

  @impl true
  def slice(%Iterator{}), do: throw(:not_implemented)

  @impl true
  def count(%Iterator{}), do: throw(:not_implemented)
  # coveralls-ignore-stop

  @impl true
  def reduce(%Iterator{}, {:halt, acc}, _fun), do: {:halted, acc}

  def reduce(%Iterator{offset: offset, index_size: index_size}, {:cont, acc}, _fun)
      when offset == index_size,
      do: {:done, acc}

  def reduce(%Iterator{} = iterator, {:cont, acc}, fun) do
    {entry, iterator} = next(iterator)

    reduce(iterator, fun.(entry, acc), fun)
  end
end
