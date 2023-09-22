defmodule Box.Wal.Iterator do
  defstruct [:fd, :path, offset: 0]

  @type t :: %__MODULE__{
          path: Path.t(),
          offset: integer(),
          fd: File.io_device()
        }

  @opts [:read, :binary]

  @spec new(Path.t()) :: t()
  def new(path) do
    path = Path.absname(path)

    struct!(__MODULE__, path: path, fd: File.open!(path, @opts))
  end
end

defimpl Enumerable, for: Box.Wal.Iterator do
  alias Box.Wal.Entry
  alias Box.Wal.Iterator

  # coveralls-ignore-start
  @impl true
  def member?(%Iterator{}, _element), do: throw(:not_implemented)

  @impl true
  def slice(%Iterator{}), do: throw(:not_implemented)

  @impl true
  def count(%Iterator{}), do: throw(:not_implemented)
  # coveralls-ignore-stop

  @impl true
  def reduce(%Iterator{offset: :eof, fd: fd}, {:cont, acc}, _reducer) do
    :ok = File.close(fd)

    {:done, acc}
  end

  def reduce(%Iterator{fd: fd, offset: offset} = iterator, {:cont, acc}, reducer) do
    with {:ok, _new_position} <- :file.position(fd, offset),
         %Entry{} = entry <- Entry.read(fd) do
      new_offset =
        case IO.binread(fd, 1) do
          :eof -> :eof
          _ -> offset + Entry.size(entry)
        end

      reduce(%{iterator | offset: new_offset}, reducer.(entry, acc), reducer)
    end
  end
end
