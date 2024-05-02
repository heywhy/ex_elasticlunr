defmodule Elasticlunr.Wal.Iterator do
  defstruct [:fd, :path, :size, offset: 0]

  @type t :: %__MODULE__{
          path: Path.t(),
          offset: integer(),
          fd: File.io_device(),
          size: non_neg_integer()
        }

  @opts [:read, :binary]

  @spec new!(Path.t()) :: t() | no_return()
  def new!(path) do
    path = Path.absname(path)
    %File.Stat{size: size} = File.stat!(path)

    attrs = %{
      path: path,
      size: size,
      fd: File.open!(path, @opts)
    }

    struct!(__MODULE__, attrs)
  end
end

defimpl Enumerable, for: Elasticlunr.Wal.Iterator do
  alias Elasticlunr.Wal.Entry
  alias Elasticlunr.Wal.Iterator

  # coveralls-ignore-start
  @impl true
  def member?(%Iterator{}, _element), do: throw(:not_implemented)

  @impl true
  def slice(%Iterator{}), do: throw(:not_implemented)

  @impl true
  def count(%Iterator{}), do: throw(:not_implemented)
  # coveralls-ignore-stop

  @impl true
  def reduce(%Iterator{offset: offset, size: size, fd: fd}, {:cont, acc}, _fun)
      when offset >= size do
    :ok = File.close(fd)

    {:done, acc}
  end

  def reduce(%Iterator{fd: fd, offset: offset} = iterator, {:cont, acc}, reducer) do
    with {:ok, ^offset} <- :file.position(fd, offset),
         %Entry{} = entry <- Entry.read!(fd),
         new_offset <- offset + Entry.size(entry) do
      reduce(%{iterator | offset: new_offset}, reducer.(entry, acc), reducer)
    end
  end
end
