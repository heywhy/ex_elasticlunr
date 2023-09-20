defmodule Box.SSTable.Iterator do
  alias Box.SSTable.Entry

  defstruct [:fd, :path, offset: 0]

  @type t :: %__MODULE__{
          path: Path.t(),
          offset: pos_integer(),
          fd: File.io_device() | :eof
        }

  @opts [:read, :binary]

  @spec new(Path.t()) :: t()
  def new(path) do
    fd = File.open!(path, @opts)

    attrs = %{
      fd: fd,
      path: path
    }

    struct!(__MODULE__, attrs)
  end

  @spec next(t()) :: {Entry.t() | nil | :file.posix() | :badarg | :terminated, t()} | no_return()
  def next(%__MODULE__{fd: fd} = iterator) when is_pid(fd) do
    case read(iterator) do
      {%Entry{} = entry, new_offset, iterator} ->
        {entry, %{iterator | offset: new_offset}}

      {nil, new_offset, iterator} ->
        :ok = File.close(fd)
        {nil, %{iterator | fd: :eof, offset: new_offset}}
    end
  end

  @spec current(t()) :: {Entry.t(), t()}
  def current(%__MODULE__{} = iterator) do
    {entry, _new_offset, iterator} = read(iterator)

    {entry, iterator}
  end

  defp read(%__MODULE__{fd: fd, offset: offset} = iterator) do
    with {:ok, _new_position} <- :file.position(fd, offset),
         <<key_size::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         <<deleted::unsigned-integer>> <- IO.binread(fd, 1),
         {key, value, value_size} <- read_kv(fd, deleted, key_size),
         <<timestamp::big-unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         entry <- Entry.new(key, value, deleted, timestamp) do
      new_offset = offset + key_size + value_size + 17

      {entry, new_offset, iterator}
    else
      {:error, reason} -> {reason, offset, iterator}
      :eof -> {nil, offset, iterator}
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

defimpl Enumerable, for: Box.SSTable.Iterator do
  alias Box.SSTable.Entry
  alias Box.SSTable.Iterator

  import Iterator, only: [next: 1]

  @impl true
  def member?(%Iterator{}, _element), do: throw(:not_implemented)

  @impl true
  def slice(%Iterator{}), do: throw(:not_implemented)

  @impl true
  def count(%Iterator{}), do: throw(:not_implemented)

  @impl true
  def reduce(%Iterator{fd: _fd}, {:halt, acc}, _fun), do: {:halted, acc}
  def reduce(%Iterator{fd: :eof}, {:cont, acc}, _fun), do: {:done, acc}

  def reduce(%Iterator{} = iterator, {:cont, acc}, fun) do
    case next(iterator) do
      {%Entry{} = entry, iterator} -> reduce(iterator, fun.(entry, acc), fun)
      {nil, iterator} -> reduce(iterator, {:cont, acc}, fun)
    end
  end
end
