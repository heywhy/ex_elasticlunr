defmodule Elasticlunr.Index.Writer do
  use Rop

  alias Elasticlunr.Filename
  alias Elasticlunr.Manifest
  alias Elasticlunr.MemTable
  alias Elasticlunr.MemTable.Entry, as: MemTableEntry
  alias Elasticlunr.Schema
  alias Elasticlunr.SSTable
  alias Elasticlunr.Utils
  alias Elasticlunr.Wal
  alias Elasticlunr.Wal.Entry, as: WalEntry
  alias Elasticlunr.Wal.Iterator

  require Logger

  defstruct [:dir, :schema, :wal, :mem_table, :mt_max_size, :manifest]

  @type t :: %__MODULE__{
          wal: nil | Wal.t(),
          dir: Path.t(),
          schema: Schema.t(),
          mt_max_size: pos_integer(),
          manifest: nil | Manifest.t(),
          mem_table: nil | MemTable.t()
        }

  @spec new(Path.t(), Schema.t(), pos_integer()) :: t()
  def new(dir, schema, mt_max_size) do
    attrs = [
      dir: dir,
      schema: schema,
      mt_max_size: mt_max_size
    ]

    struct!(__MODULE__, attrs)
  end

  @spec recover(t()) :: {:ok, t()} | {:error, term()}
  def recover(%__MODULE__{} = writer) do
    create_db_if_missing(writer) >>>
      recover_manifest() >>>
      find_log_files() >>>
      recover_from_logs() >>>
      reuse_last_log() >>>
      remove_obsolete_files() >>>
      patch_writer()
  end

  defp remove_obsolete_files(%{dir: dir, manifest: manifest} = state) do
    known_files = Manifest.known_files(manifest)

    keep? = fn path ->
      case Filename.parse(path) do
        {:current, _number} -> true
        {:log, number} -> number >= manifest.log_number
        {:manifest, number} -> number >= manifest.number
        {:tmp, number} -> Enum.member?(known_files, number)
      end
    end

    files_to_delete =
      dir
      |> db_files()
      |> Enum.reduce([], fn path, acc ->
        case keep?.(path) do
          false -> [path] ++ acc
          true -> acc
        end
      end)

    Enum.each(files_to_delete, &File.rm/1)

    {:ok, state}
  end

  defp patch_writer(%{wal: wal, manifest: manifest, mem_table: mem_table, writer: writer}) do
    {:ok, %{writer | manifest: manifest, mem_table: mem_table, wal: wal}}
  end

  defp reuse_last_log(%{log_files: [], dir: dir, manifest: manifest} = params) do
    {number, manifest} = Manifest.new_file_number(manifest)
    changes = %{log_number: number}
    wal = Wal.create(dir, number)

    with {:ok, manifest} <- Manifest.apply_and_log(manifest, changes) do
      params
      |> Map.put(:wal, wal)
      |> Map.put(:manifest, manifest)
      |> then(&{:ok, &1})
    end
  end

  defp reuse_last_log(
         %{dir: dir, compactions: 0, last_log_number: log_number, manifest: manifest} =
           state
       ) do
    dir
    |> Wal.create(log_number)
    |> then(&Map.put(state, :wal, &1))
    |> then(&%{&1 | manifest: manifest})
    |> then(&{:ok, &1})
  end

  defp recover_from_logs(%{log_files: []} = state) do
    {:ok, Map.put(state, :mem_table, MemTable.new())}
  end

  defp recover_from_logs(
         %{dir: dir, log_files: log_files, manifest: manifest, writer: writer} = state
       ) do
    mergeable_fields = [:manifest, :mem_table, :compactions, :last_log_number]

    params = %{
      dir: dir,
      manifest: manifest,
      mem_table: MemTable.new(),
      mt_max_size: writer.mt_max_size,
      last_log_number: List.last(log_files)
    }

    mark_file_number = fn %{manifest: manifest, log_number: log_number} = params ->
      %{params | manifest: Manifest.use_file_number(manifest, log_number)}
    end

    merge_state_and_result = fn state, params ->
      params
      |> Map.take(mergeable_fields)
      |> then(&Map.merge(state, &1))
    end

    log_files
    |> Enum.reduce_while(params, fn log_number, params ->
      params
      |> Map.put(:compactions, 0)
      |> Map.put(:log_number, log_number)
      |> recover_log_file()
      |> case do
        %{} = result -> {:cont, mark_file_number.(result)}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      %{} = result -> {:ok, merge_state_and_result.(state, result)}
      error -> error
    end
  end

  defp recover_log_file(%{dir: dir, log_number: log_number} = params) do
    Logger.info("Recovering log #{log_number}")

    update_mt = fn mem_table, entry ->
      case entry do
        %WalEntry{deleted: true, key: key, timestamp: ts} ->
          MemTable.remove(mem_table, key, ts)

        %WalEntry{key: key, value: value, timestamp: ts} ->
          MemTable.set(mem_table, key, value, ts)
      end
    end

    dir
    |> Filename.log(log_number)
    |> Iterator.new()
    |> Enum.reduce_while(params, fn entry, acc ->
      %{mem_table: mt, compactions: c, mt_max_size: mms} = acc
      mt = update_mt.(mt, entry)

      with {true, mt} <- {MemTable.size(mt) >= mms, mt},
           :ok <- write_to_level_0(mt, dir) do
        {:cont, %{acc | mem_table: MemTable.new(), compactions: c + 1}}
      else
        {false, mem_table} -> {:cont, Map.put(acc, :mem_table, mem_table)}
        error -> {:halt, error}
      end
    end)
    |> case do
      %{mem_table: mt, log_number: ln, last_log_number: lln} = p when ln != lln ->
        # Write to level 0 in case the log got hanging due to incomplete compaction.
        # See `Elasticlunr.Server.Writer.flush_async/1`
        :ok = write_to_level_0(mt, dir)

        %{p | mem_table: MemTable.new()}

      p ->
        p
    end
  end

  defp write_to_level_0(mem_table, dir) do
    SSTable.flush(mem_table, dir)
    # TODO: return appropriate result
    :ok
  end

  defp find_log_files(%{dir: dir, manifest: manifest} = state) do
    known_files = Manifest.known_files(manifest)

    dir
    |> db_files()
    |> extract_log_files(known_files)
    # TODO: log corruption error due to missing files
    |> then(&elem(&1, 1))
    |> then(&Map.put(state, :log_files, &1))
    |> then(&{:ok, &1})
  end

  defp extract_log_files(files, known_files) do
    Enum.reduce(files, {known_files, []}, fn path, {known_files, logs} ->
      case Filename.parse(path) do
        {:log, number} ->
          known_files
          |> MapSet.delete(number)
          |> then(&{&1, [number] ++ logs})

        {_type, number} ->
          known_files
          |> MapSet.delete(number)
          |> then(&{&1, logs})
      end
    end)
  end

  defp db_files(path) do
    path
    |> Path.join("*")
    |> Path.wildcard()
  end

  defp recover_manifest(%{dir: dir} = state) do
    path = Filename.current(dir)

    with {:ok, content} <- File.read(path),
         manifest_path = Path.join(dir, content),
         {:ok, manifest} <- Manifest.from_path(manifest_path) do
      {:ok, Map.put(state, :manifest, manifest)}
    end
  end

  defp create_db_if_missing(%{dir: dir} = writer) do
    path = Filename.current(dir)

    with false <- File.exists?(path),
         :ok <- new_db(dir) do
      {:ok, %{dir: dir, writer: writer}}
    else
      true -> {:ok, %{dir: dir, writer: writer}}
      error -> error
    end
  end

  defp new_db(dir) do
    path = Filename.manifest(dir, 1)

    with :ok <- File.touch(path),
         manifest = Manifest.new(1, dir),
         {:ok, manifest} <- Manifest.apply_and_log(manifest, %{next_file_number: 2}),
         :ok <- Manifest.close(manifest) do
      set_current_manifest(dir, 1)
    else
      error ->
        File.rm(path)
        error
    end
  end

  defp set_current_manifest(dir, number) do
    current = Filename.current(dir)
    tmp = Filename.temp(dir, number)
    manifest = Filename.manifest(dir, number)
    content = Path.basename(manifest)

    with :ok <- File.write(tmp, content),
         :ok <- File.rename(tmp, current) do
      :ok
    else
      {:error, reason} ->
        File.rm(tmp)
        {:error, reason}
    end
  end

  @spec clone(t()) :: t()
  def clone(%__MODULE__{dir: dir, manifest: manifest} = writer) do
    {number, manifest} = Manifest.new_file_number(manifest)

    %{writer | manifest: manifest, wal: Wal.create(dir, number), mem_table: MemTable.new()}
  end

  @spec buffer_filled?(t()) :: boolean()
  def buffer_filled?(%__MODULE__{mem_table: mem_table, mt_max_size: mt_max_size}) do
    MemTable.size(mem_table) >= mt_max_size
  end

  @spec close(t()) :: :ok | no_return()
  def close(%__MODULE__{wal: wal}) do
    Wal.close(wal)
  end

  @spec get(t(), String.t()) :: nil | map()
  def get(%__MODULE__{mem_table: mem_table, schema: schema}, id) do
    with id <- Utils.id_from_string(id),
         %MemTableEntry{deleted: false, value: value} <- MemTable.get(mem_table, id),
         value <- Schema.binary_to_document(schema, value) do
      Map.put(value, :id, Utils.id_to_string(id))
    else
      %MemTableEntry{deleted: true} -> nil
      nil -> nil
    end
  end

  @spec remove(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def remove(%__MODULE__{mem_table: mem_table, wal: wal} = writer, id) do
    with id <- Utils.id_from_string(id),
         timestamp <- Utils.now(),
         mem_table <- MemTable.remove(mem_table, id, timestamp),
         {:ok, wal} <- Wal.remove(wal, id, timestamp),
         :ok <- Wal.flush(wal),
         writer <- %{writer | wal: wal, mem_table: mem_table} do
      {:ok, writer}
    end
  end

  @spec save(t(), map()) :: {map(), t()} | no_return()
  def save(%__MODULE__{} = writer, %{} = document) do
    {document, writer} = save_document(document, writer)

    :ok = Wal.flush(writer.wal)

    {document, writer}
  end

  @spec save_all(t(), [map()]) :: t() | no_return()
  def save_all(%__MODULE__{} = writer, documents) do
    documents
    |> Enum.reduce(writer, fn document, writer ->
      document
      |> save_document(writer)
      |> elem(1)
    end)
    |> tap(&(:ok = Wal.flush(&1.wal)))
  end

  defp save_document(document, %{schema: schema} = writer) do
    {id, document} =
      document
      # drop the struct key
      |> Map.drop([:__struct__])
      |> Map.replace_lazy(:id, fn
        nil -> Utils.new_id()
        value -> Utils.id_from_string(value)
      end)
      |> Map.pop!(:id)

    with timestamp <- Utils.now(),
         value <- Schema.document_to_binary(schema, document),
         mem_table <- MemTable.set(writer.mem_table, id, value, timestamp),
         {:ok, wal} <- Wal.set(writer.wal, id, value, timestamp),
         document <- Map.put(document, :id, Utils.id_to_string(id)) do
      {document, %{writer | wal: wal, mem_table: mem_table}}
    end
  end
end
