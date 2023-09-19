defmodule Box.SSTable.Iterator do
  alias Box.SSTable.Entry

  defstruct [:fd, :path, :count, :offset, :lower_bound, :upper_bound]

  @type t :: %__MODULE__{
          path: Path.t(),
          offset: integer(),
          count: pos_integer(),
          fd: File.io_device(),
          lower_bound: binary(),
          upper_bound: binary()
        }

  @opts [:read, :binary]

  @spec new(Path.t()) :: t()
  def new(path) do
    with fd <- File.open!(path, @opts),
         <<count::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         <<lb_size::unsigned-integer>> <- IO.binread(fd, 1),
         <<ub_size::unsigned-integer>> <- IO.binread(fd, 1),
         <<lb::binary>> <- IO.binread(fd, lb_size),
         <<ub::binary>> <- IO.binread(fd, ub_size) do
      attrs = %{
        fd: fd,
        path: path,
        count: count,
        lower_bound: lb,
        upper_bound: ub,
        offset: lb_size + ub_size + 10
      }

      struct!(__MODULE__, attrs)
    end
  end

  @spec next(t()) :: {Entry.t() | nil | :file.posix() | :badarg | :terminated, t()} | no_return()
  def next(%__MODULE__{fd: fd, offset: offset} = iterator) do
    with {:ok, _new_position} <- :file.position(fd, offset),
         <<key_size::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         <<deleted::unsigned-integer>> <- IO.binread(fd, 1),
         {key, value, value_size} <- read_kv(fd, deleted, key_size),
         <<timestamp::big-unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         entry <- Entry.new(key, value, deleted, timestamp) do
      offset = offset + key_size + value_size + 17

      {entry, %{iterator | offset: offset}}
    else
      {:error, reason} ->
        {reason, iterator}

      _ ->
        :ok = File.close(fd)
        {nil, iterator}
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
  def count(%Iterator{count: count}), do: {:ok, count}

  @impl true
  def reduce(%Iterator{fd: _fd}, {:halt, acc}, _fun), do: {:halted, acc}
  def reduce(%Iterator{offset: -1}, {:cont, acc}, _fun), do: {:done, acc}

  def reduce(%Iterator{} = iterator, {:cont, acc}, fun) do
    case next(iterator) do
      {%Entry{} = entry, iterator} -> reduce(iterator, fun.(entry, acc), fun)
      {nil, iterator} -> reduce(%{iterator | offset: -1}, {:cont, acc}, fun)
    end
  end
end
