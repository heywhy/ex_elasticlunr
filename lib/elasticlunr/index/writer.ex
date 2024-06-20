defmodule Elasticlunr.Index.Writer do
  use Rop

  alias Elasticlunr.Filename
  alias Elasticlunr.Fs
  alias Elasticlunr.Manifest
  alias Elasticlunr.Manifest.Changes
  alias Elasticlunr.MemTable
  alias Elasticlunr.MemTable.Entry, as: MemTableEntry
  alias Elasticlunr.Options
  alias Elasticlunr.Schema
  alias Elasticlunr.SSTable
  alias Elasticlunr.Utils
  alias Elasticlunr.Wal
  alias Elasticlunr.Wal.Entry, as: WalEntry
  alias Elasticlunr.Wal.Iterator

  require Logger

  @enforce_keys [:dir, :schema, :options]
  defstruct [:dir, :schema, :options, :wal, :mem_table, :manifest]

  @type t :: %__MODULE__{
          wal: nil | Wal.t(),
          dir: Path.t(),
          schema: Schema.t(),
          options: Options.t(),
          manifest: nil | Manifest.t(),
          mem_table: nil | MemTable.t()
        }

  @spec new(Path.t(), Schema.t()) :: t()
  def new(dir, %Schema{options: options} = schema) do
    struct!(__MODULE__, dir: dir, schema: schema, options: options)
  end

  @spec manifest(t()) :: Manifest.t()
  def manifest(%__MODULE__{manifest: manifest}), do: manifest

  @spec recover(t()) :: {:ok, t()} | {:error, term()}
  def recover(%__MODULE__{} = writer) do
    create_db_if_missing(writer) >>>
      recover_manifest() >>>
      find_log_files() >>>
      recover_from_logs() >>>
      reuse_last_log() >>>
      bind(patch_writer) >>>
      bind(remove_obsolete_files)
  end

  @spec remove_obsolete_files(t()) :: t()
  def remove_obsolete_files(%__MODULE__{dir: dir, manifest: manifest} = writer) do
    known_files = Manifest.known_files(manifest)

    keep? = fn path, manifest ->
      case Filename.parse(path) do
        {:current, _number} -> true
        {:log, number} -> number >= manifest.log_number
        {:manifest, number} -> number >= manifest.number
        {tag, number} when tag in [:sst, :tmp] -> MapSet.member?(known_files, number)
      end
    end

    :ok =
      dir
      |> Fs.db_files()
      |> Enum.each(&unless keep?.(&1, manifest), do: File.rm(&1))

    writer
  end

  defp patch_writer(%{wal: wal, manifest: manifest, mem_table: mem_table, writer: writer}) do
    %{writer | manifest: manifest, mem_table: mem_table, wal: wal}
  end

  defp reuse_last_log(
         %{log_files: log_files, compactions: compactions, dir: dir, manifest: manifest} = params
       )
       when log_files == [] or compactions >= 1 do
    number = Manifest.new_file_number(manifest)
    changes = Changes.set_log_number(%Changes{}, number)

    with {:ok, manifest} <- Manifest.apply_and_log(manifest, changes) do
      wal = Wal.create(dir, number)

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
    %Changes{}
    |> Changes.set_log_number(log_number)
    |> then(&Manifest.apply_and_log(manifest, &1))
    |> case do
      {:ok, manifest} ->
        dir
        |> Wal.create(log_number)
        |> then(&Map.put(state, :wal, &1))
        |> then(&%{&1 | manifest: manifest})
        |> then(&{:ok, &1})

      error ->
        error
    end
  end

  defp recover_from_logs(%{log_files: []} = state) do
    state
    |> Map.put(:compactions, 0)
    |> Map.put(:mem_table, MemTable.new())
    |> then(&{:ok, &1})
  end

  defp recover_from_logs(
         %{dir: dir, log_files: log_files, manifest: manifest, options: options} = state
       ) do
    mergeable_fields = [:manifest, :mem_table, :compactions, :last_log_number]

    params = %{
      dir: dir,
      options: options,
      manifest: manifest,
      mem_table: MemTable.new(),
      last_log_number: List.last(log_files),
      max_buffer_size: options.max_buffer_size
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

  defp recover_log_file(%{dir: dir, log_number: log_number, options: options} = params) do
    Logger.info("Recovering log #{log_number}")

    update_mt = fn mem_table, entry ->
      case entry do
        %WalEntry{deleted: true, key: key, timestamp: ts} ->
          MemTable.remove(mem_table, key, ts)

        %WalEntry{key: key, value: value, timestamp: ts} ->
          MemTable.set(mem_table, key, value, ts)
      end
    end

    flush_mt = fn mem_table, dir, manifest, max_file_size ->
      opts = [max_file_size: max_file_size]
      fun = Manifest.new_file_number_fn(manifest)

      with true <- MemTable.size(mem_table) > 0,
           {:ok, file_metas} <- SSTable.flush(mem_table, dir, fun, opts) do
        changes = Changes.add_files(%Changes{}, 0, file_metas)

        Manifest.apply_and_log(manifest, changes)
      else
        false -> {:ok, manifest}
        error -> error
      end
    end

    dir
    |> Filename.log(log_number)
    |> Iterator.new!()
    |> Enum.reduce_while(params, fn entry, acc ->
      %{mem_table: mt, compactions: c, manifest: manifest, max_buffer_size: mbs} = acc
      mt = update_mt.(mt, entry)

      with {true, mt} <- {MemTable.size(mt) >= mbs, mt},
           {:ok, manifest} <- flush_mt.(mt, dir, manifest, options.max_file_size) do
        {:cont, %{acc | mem_table: MemTable.new(), manifest: manifest, compactions: c + 1}}
      else
        {false, mem_table} -> {:cont, Map.put(acc, :mem_table, mem_table)}
        error -> {:halt, error}
      end
    end)
    |> case do
      %{mem_table: mt, manifest: manifest, log_number: ln, last_log_number: lln} = p
      when ln != lln ->
        # Write to level 0 in case the log got hanging due to incomplete compaction.
        # See `Elasticlunr.Server.Writer.flush_async/1`
        {:ok, manifest} = flush_mt.(mt, dir, manifest, options.max_file_size)

        %{p | compactions: 1, mem_table: MemTable.new(), manifest: manifest}

      %{} = p ->
        p

      error ->
        error
    end
  end

  defp find_log_files(%{dir: dir, manifest: manifest} = state) do
    current_log = Manifest.current_log(manifest)
    known_files = Manifest.known_files(manifest)

    dir
    |> Fs.db_files()
    |> extract_log_files(known_files, current_log)
    |> then(fn {missing_files, log_files} -> {MapSet.to_list(missing_files), log_files} end)
    |> case do
      {[], logs} ->
        logs
        |> Enum.sort()
        |> then(&Map.put(state, :log_files, &1))
        |> then(&{:ok, &1})

      {missing_files, _logs} ->
        file = List.first(missing_files)
        count = Enum.count(missing_files)

        {:error, "#{count} missing file(s): #{file}"}
    end
  end

  defp extract_log_files(files, known_files, current_log) do
    Enum.reduce(files, {known_files, []}, fn path, {known_files, logs} ->
      case Filename.parse(path) do
        {:log, number} when number >= current_log ->
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

  defp recover_manifest(%{dir: dir} = state) do
    path = Filename.current(dir)

    with {:ok, content} <- File.read(path),
         manifest_path = Path.join(dir, content),
         {:ok, manifest} <- Manifest.from_path(manifest_path) do
      {:ok, Map.put(state, :manifest, manifest)}
    end
  end

  defp create_db_if_missing(%{dir: dir, options: options} = writer) do
    path = Filename.current(dir)
    state = %{dir: dir, options: options, writer: writer}

    with false <- File.exists?(path),
         :ok <- new_db(dir, options) do
      {:ok, state}
    else
      true -> {:ok, state}
      error -> error
    end
  end

  defp new_db(dir, options) do
    path = Filename.manifest(dir, 1)

    with :ok <- File.touch(path),
         manifest = Manifest.new(1, dir, options),
         changes = Changes.set_next_file_number(%Changes{}, 2),
         {:ok, manifest} <- Manifest.apply_and_log(manifest, changes),
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

  @spec buffer_filled?(t()) :: boolean()
  def buffer_filled?(%__MODULE__{mem_table: mem_table, options: options}) do
    MemTable.size(mem_table) >= options.max_buffer_size
  end

  @spec close(t()) :: :ok | no_return()
  def close(%__MODULE__{wal: wal}), do: Wal.close(wal)

  @spec get(t(), String.t()) :: nil | map()
  def get(%__MODULE__{mem_table: mem_table, schema: schema}, id) do
    with id <- Utils.id_from_string(id),
         %MemTableEntry{deleted: false, value: value} <- MemTable.get(mem_table, id),
         value <- Schema.decode!(schema, value) do
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
         value <- Schema.encode(schema, document),
         mem_table <- MemTable.set(writer.mem_table, id, value, timestamp),
         {:ok, wal} <- Wal.set(writer.wal, id, value, timestamp),
         document <- Map.put(document, :id, Utils.id_to_string(id)) do
      {document, %{writer | wal: wal, mem_table: mem_table}}
    end
  end
end
