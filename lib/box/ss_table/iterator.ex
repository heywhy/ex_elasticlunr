defmodule Box.SSTable.Iterator do
  alias Box.Fs
  alias Box.SSTable.Entry
  alias Box.SSTable.Shared

  defstruct [:fd, :path, offset: 0]

  @type t :: %__MODULE__{
          path: Path.t(),
          fd: File.io_device(),
          offset: pos_integer() | :eof
        }

  @spec new(Path.t()) :: t()
  def new(path) do
    fd =
      path
      |> Shared.segment_file()
      |> Fs.open()

    struct!(__MODULE__, fd: fd, path: path)
  end

  @spec eof?(t()) :: boolean()
  def eof?(%__MODULE__{offset: offset}), do: offset == :eof

  @spec next(t()) :: {Entry.t(), t()} | no_return()
  def next(%__MODULE__{offset: offset} = iterator) when is_integer(offset) do
    {entry, new_offset, iterator} = read(iterator)

    case %{iterator | offset: new_offset} do
      %__MODULE__{fd: fd, offset: :eof} = iterator ->
        :ok = File.close(fd)
        {entry, iterator}

      %__MODULE__{} = iterator ->
        {entry, iterator}
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
      new_offset =
        case IO.binread(fd, 1) do
          :eof -> :eof
          _ -> offset + key_size + value_size + 17
        end

      {entry, new_offset, iterator}
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
  alias Box.SSTable.Iterator

  import Iterator, only: [next: 1]

  @impl true
  def member?(%Iterator{}, _element), do: throw(:not_implemented)

  @impl true
  def slice(%Iterator{}), do: throw(:not_implemented)

  @impl true
  def count(%Iterator{}), do: throw(:not_implemented)

  @impl true
  def reduce(%Iterator{}, {:halt, acc}, _fun), do: {:halted, acc}
  def reduce(%Iterator{offset: :eof}, {:cont, acc}, _fun), do: {:done, acc}

  def reduce(%Iterator{} = iterator, {:cont, acc}, fun) do
    {entry, iterator} = next(iterator)

    reduce(iterator, fun.(entry, acc), fun)
  end
end
