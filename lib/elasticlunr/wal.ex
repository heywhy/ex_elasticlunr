defmodule Elasticlunr.Wal do
  alias Elasticlunr.MemTable
  alias Elasticlunr.Telemeter
  alias Elasticlunr.Utils
  alias Elasticlunr.Wal.Entry

  alias __MODULE__.Iterator

  defstruct [:fd, :path]

  @type t :: %__MODULE__{
          path: Path.t(),
          fd: File.io_device()
        }

  @opts [:append, :binary]

  @load_event :load_wal
  @close_event :close_wal

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

    wals = list(dir)
    metadata = %{index: Path.basename(dir), count: Enum.count(wals)}

    Telemeter.track(@load_event, metadata, fn ->
      {wal, mem_table, total_size} =
        Enum.reduce(
          wals,
          {create(dir), MemTable.new(), 0},
          fn path, {new_wal, mem_table, total_size} ->
            wal = from_path(path)
            %File.Stat{size: size} = File.stat!(path)

            result = Enum.reduce(iterator(wal), {new_wal, mem_table}, reducer)

            :ok = close(wal)

            File.rm!(path)

            Tuple.append(result, total_size + size)
          end
        )

      {{wal, mem_table}, %{total_size: total_size}}
    end)
  end

  @spec flush(t()) :: :ok | {:error, atom()}
  def flush(%__MODULE__{fd: fd}), do: :file.sync(fd)

  @spec iterator(t()) :: Enumerable.t()
  def iterator(%__MODULE__{path: path}), do: Iterator.new(path)

  @spec close(t()) :: :ok | no_return()
  def close(%__MODULE__{fd: fd, path: path} = wal) do
    metadata = %{
      index: Path.basename(path),
      file: Path.basename(path)
    }

    Telemeter.track(@close_event, metadata, fn ->
      :ok = flush(wal)
      :ok = File.close(fd)
      %File.Stat{size: size} = File.stat!(path)

      {:ok, %{size: size}}
    end)
  end

  @spec delete(t()) :: :ok | no_return()
  def delete(%__MODULE__{path: path} = wal) do
    :ok = close(wal)
    :ok = File.rm(path)
  end

  @spec set(t(), binary(), binary(), pos_integer()) :: {:ok, t()} | {:error, term()}
  def set(%__MODULE__{fd: fd} = wal, key, value, timestamp) do
    with %Entry{} = entry <- Entry.new(key, value, false, timestamp),
         data <- Entry.to_binary(entry),
         :ok <- IO.binwrite(fd, data) do
      {:ok, wal}
    end
  end

  @spec remove(t(), binary(), pos_integer()) :: {:ok, t()} | {:error, term()}
  def remove(%__MODULE__{fd: fd} = wal, key, timestamp) do
    with %Entry{} = entry <- Entry.new(key, nil, true, timestamp),
         data <- Entry.to_binary(entry),
         :ok <- IO.binwrite(fd, data) do
      {:ok, wal}
    end
  end
end
