defmodule Box.SSTable.Iterator do
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
    with path <- Path.absname(path),
         fd <- File.open!(path, @opts),
         <<count::unsigned-integer>> <- IO.binread(fd, 1),
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
        offset: lb_size + ub_size + 3
      }

      struct!(__MODULE__, attrs)
    end
  end
end

defimpl Enumerable, for: Box.SSTable.Iterator do
  alias Box.SSTable.Entry
  alias Box.SSTable.Iterator

  @impl true
  def member?(%Iterator{lower_bound: lb, upper_bound: ub}, element),
    do: {:ok, element >= lb and element <= ub}

  @impl true
  def slice(%Iterator{}), do: throw(:not_implemented)

  @impl true
  def count(%Iterator{count: count}), do: {:ok, count}

  @impl true
  def reduce(%Iterator{fd: _fd}, {:halt, acc}, _fun), do: {:halted, acc}

  def reduce(%Iterator{offset: -1, fd: fd}, {:cont, acc}, _fun) do
    :ok = File.close(fd)

    {:done, acc}
  end

  def reduce(%Iterator{fd: fd, offset: offset} = iterator, {:cont, acc}, fun) do
    with {:ok, _new_position} <- :file.position(fd, offset),
         <<key_size::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         <<deleted::unsigned-integer>> <- IO.binread(fd, 1),
         {key, value, value_size} <- read_kv(fd, deleted, key_size),
         <<timestamp::big-unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         entry <- Entry.new(key, value, deleted, timestamp) do
      offset = offset + key_size + value_size + 17
      reduce(%{iterator | offset: offset}, fun.(entry, acc), fun)
    else
      _ -> reduce(%{iterator | offset: -1}, {:cont, acc}, fun)
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
