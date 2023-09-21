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

  @impl true
  def member?(%Iterator{}, _element), do: throw(:not_implemented)

  @impl true
  def slice(%Iterator{}), do: throw(:not_implemented)

  @impl true
  def count(%Iterator{}), do: throw(:not_implemented)

  @impl true
  def reduce(%Iterator{offset: :eof, fd: fd}, {:cont, acc}, _reducer) do
    :ok = File.close(fd)

    {:done, acc}
  end

  def reduce(%Iterator{fd: fd, offset: offset} = iterator, {:cont, acc}, reducer) do
    with {:ok, _new_position} <- :file.position(fd, offset),
         <<key_size::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         <<deleted::unsigned-integer>> <- IO.binread(fd, 1),
         {key, value, value_size} <- read_kv(fd, deleted, key_size),
         <<timestamp::big-unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         entry <- Entry.new(key, value, deleted, timestamp) do
      new_offset =
        case IO.binread(fd, 1) do
          :eof -> :eof
          _ -> offset + key_size + value_size + 17
        end

      reduce(%{iterator | offset: new_offset}, reducer.(entry, acc), reducer)
    end
  end

  defp read_kv(fd, 0, key_size) do
    with <<value_size::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         key <- IO.binread(fd, key_size),
         value <- IO.binread(fd, value_size) do
      {key, value, value_size + 8}
    end
  end

  defp read_kv(fd, 1, key_size) do
    with key <- IO.binread(fd, key_size) do
      {key, nil, 0}
    end
  end
end
