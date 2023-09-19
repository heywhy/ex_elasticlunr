defmodule Box.Wal do
  alias Box.MemTable
  alias Box.Utils
  alias Box.Wal.Entry

  alias __MODULE__.Iterator

  defstruct [:fd, :path]

  @type t :: %__MODULE__{
          path: Path.t(),
          fd: File.io_device()
        }

  @opts [:append, :binary]

  defp new(path) do
    path = Path.absname(path)

    struct!(__MODULE__, path: path, fd: File.open!(path, @opts))
  end

  @spec create(Path.t()) :: t()
  def create(dir) do
    now = Utils.now()
    path = Path.join(dir, "#{now}.wal")

    new(path)
  end

  @spec from_path(Path.t()) :: t()
  def from_path(path), do: new(path)

  @spec list(Path.t()) :: [Path.t()]
  def list(dir) do
    dir
    |> Path.join("*.wal")
    |> Path.wildcard()
  end

  @spec load_from_dir(Path.t()) :: {t(), MemTable.t()} | no_return()
  def load_from_dir(dir) do
    reducer = fn %Entry{} = entry, {new_wal, mem_table} ->
      case entry.deleted do
        true ->
          mem_table = MemTable.remove(mem_table, entry.key, entry.timestamp)
          {:ok, new_wal} = remove(new_wal, entry.key, entry.timestamp)

          {new_wal, mem_table}

        false ->
          mem_table = MemTable.set(mem_table, entry.key, entry.value, entry.timestamp)
          {:ok, new_wal} = set(new_wal, entry.key, entry.value, entry.timestamp)

          {new_wal, mem_table}
      end
    end

    Enum.reduce(list(dir), {create(dir), MemTable.new()}, fn path, acc ->
      wal = from_path(path)

      result = Enum.reduce(iterator(wal), acc, reducer)

      :ok = close(wal)

      File.rm!(path)

      result
    end)
  end

  @spec flush(t()) :: :ok | {:error, atom()}
  def flush(%__MODULE__{fd: fd}), do: :file.sync(fd)

  @spec iterator(t()) :: Enumerable.t()
  def iterator(%__MODULE__{path: path}), do: Iterator.new(path)

  @spec close(t()) :: :ok | no_return()
  def close(%__MODULE__{fd: fd} = wal) do
    :ok = flush(wal)
    :ok = File.close(fd)
  end

  @spec delete(t()) :: :ok | no_return()
  def delete(%__MODULE__{path: path} = wal) do
    :ok = close(wal)
    :ok = File.rm(path)
  end

  @spec set(t(), binary(), binary(), pos_integer()) :: {:ok, t()} | {:error, term()}
  def set(%__MODULE__{fd: fd} = wal, key, value, timestamp) do
    with data <- kv_to_binary(key, value, timestamp),
         :ok <- IO.binwrite(fd, data) do
      {:ok, wal}
    end
  end

  @spec remove(t(), binary(), pos_integer()) :: {:ok, t()} | {:error, term()}
  def remove(%__MODULE__{fd: fd} = wal, key, timestamp) do
    with data <- deleted_key_to_binary(key, timestamp),
         :ok <- IO.binwrite(fd, data) do
      {:ok, wal}
    end
  end

  defp kv_to_binary(key, value, timestamp) do
    key_size = byte_size(key)
    key_size_data = <<key_size::unsigned-integer-size(64)>>

    deleted_data = <<0::unsigned-integer>>

    value_size = byte_size(value)
    value_size_data = <<value_size::unsigned-integer-size(64)>>

    timestamp_data = <<timestamp::big-unsigned-integer-size(64)>>

    sizes_data = <<key_size_data::binary, deleted_data::binary, value_size_data::binary>>

    kv_data = <<key::binary, value::binary>>

    <<sizes_data::binary, kv_data::binary, timestamp_data::binary>>
  end

  defp deleted_key_to_binary(key, timestamp) do
    key_size = byte_size(key)
    key_size_data = <<key_size::unsigned-integer-size(64)>>

    deleted_data = <<1::unsigned-integer>>

    timestamp_data = <<timestamp::big-unsigned-integer-size(64)>>

    sizes_data = <<key_size_data::binary, deleted_data::binary>>

    <<sizes_data::binary, key::binary, timestamp_data::binary>>
  end
end
