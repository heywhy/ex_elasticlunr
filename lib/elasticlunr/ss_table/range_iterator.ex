defmodule Elasticlunr.SSTable.RangeIterator do
  alias Elasticlunr.Fs
  alias Elasticlunr.SSTable.Entry
  alias Elasticlunr.SSTable.Shared

  defstruct [:fd, :path, :start, :stop, :offset]
  @type range :: {pos_integer(), pos_integer()}

  @type t :: %__MODULE__{
          path: Path.t(),
          fd: File.io_device(),
          start: pos_integer(),
          stop: pos_integer(),
          offset: pos_integer()
        }

  @spec new(Path.t(), range()) :: t()
  def new(path, {start, stop}) do
    fd =
      path
      |> Shared.segment_file()
      |> Fs.open()

    attrs = %{
      fd: fd,
      path: path,
      stop: stop,
      start: start,
      offset: start
    }

    struct!(__MODULE__, attrs)
  end
end

defimpl Enumerable, for: Elasticlunr.SSTable.RangeIterator do
  alias Elasticlunr.SSTable.Entry
  alias Elasticlunr.SSTable.RangeIterator

  # coveralls-ignore-start
  @impl true
  def member?(%RangeIterator{}, _element), do: throw(:not_implemented)

  @impl true
  def slice(%RangeIterator{}), do: throw(:not_implemented)

  @impl true
  def count(%RangeIterator{}), do: throw(:not_implemented)
  # coveralls-ignore-stop

  @impl true
  def reduce(%RangeIterator{fd: fd}, {:halt, acc}, _fun) do
    :ok = File.close(fd)
    {:halted, acc}
  end

  def reduce(%RangeIterator{fd: fd, offset: offset, stop: stop}, {:cont, acc}, _fun)
      when offset < 0 or offset > stop do
    :ok = File.close(fd)
    {:done, acc}
  end

  def reduce(%RangeIterator{fd: fd, offset: offset} = iterator, {:cont, acc}, fun) do
    with {:ok, _new_position} <- :file.position(fd, offset),
         %Entry{} = entry <- Entry.read(fd),
         new_offset <- offset + Entry.size(entry),
         iterator <- %{iterator | offset: new_offset} do
      reduce(iterator, fun.(entry, acc), fun)
    end
  end
end
