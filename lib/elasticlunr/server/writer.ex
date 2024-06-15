defmodule Elasticlunr.Server.Writer do
  use GenServer

  alias Elasticlunr.BackgroundTaskSupervisor
  alias Elasticlunr.CompactionController
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Index.Writer
  alias Elasticlunr.Manifest
  alias Elasticlunr.Manifest.Changes
  alias Elasticlunr.MemTable
  alias Elasticlunr.PubSub
  alias Elasticlunr.SSTable
  alias Elasticlunr.Wal

  require Logger

  @enforce_keys [:flush_fn, :writer]
  defstruct [:task, :tmp, :flush_fn, :writer]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, hibernate_after: 5_000)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    opts = Keyword.validate!(opts, [:dir, :schema, flush_fn: &flush_async/1])

    dir = Keyword.fetch!(opts, :dir)
    schema = Keyword.fetch!(opts, :schema)
    writer = Writer.new(dir, schema)

    :ok = Logger.metadata(index: schema.name)

    case Writer.recover(writer) do
      {:ok, writer} ->
        state = %__MODULE__{flush_fn: opts[:flush_fn], writer: writer}

        {:ok, maybe_schedule_compactions(state)}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # Callbacks
  @impl true
  def handle_call({:save, document}, _from, %__MODULE__{} = state) do
    state = write_to_disk_if_needed(state)
    {document, writer} = Writer.save(state.writer, document)

    {:reply, document, %{state | writer: writer}}
  end

  def handle_call({:save_all, documents}, _from, %__MODULE__{} = state) do
    state = write_to_disk_if_needed(state)
    writer = Writer.save_all(state.writer, documents)

    {:reply, :ok, %{state | writer: writer}}
  end

  def handle_call({:delete, id}, _from, %__MODULE__{} = state) do
    state = write_to_disk_if_needed(state)

    case Writer.remove(state.writer, id) do
      {:ok, writer} -> {:reply, :ok, %{state | writer: writer}}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:get, id}, _from, %__MODULE__{tmp: tmp, writer: writer} = state) do
    with nil <- Writer.get(writer, id),
         writer when not is_nil(writer) <- tmp do
      {:reply, Writer.get(writer, id), state}
    else
      value -> {:reply, value, state}
    end
  end

  @impl true
  def handle_info(
        {ref, [%FileMeta{} | _] = file_metas},
        %__MODULE__{task: %Task{ref: ref}} = state
      ) do
    Process.demonitor(ref, [:flush])

    case handle_info({:add_file, file_metas}, state) do
      {:noreply, state} -> {:noreply, %{state | task: nil, tmp: nil}}
      error -> error
    end
  end

  def handle_info(
        {:add_file, [%FileMeta{} | _] = file_metas},
        %__MODULE__{writer: writer} = state
      ) do
    file_metas = Enum.filter(file_metas, &(&1.size > 0))

    with file_metas when file_metas != [] <- file_metas,
         {:ok, writer} <- add_files_to_manifest(file_metas, writer),
         %Writer{schema: schema} <- writer do
      publish_new_files!(schema.name, file_metas)

      state
      |> Map.put(:writer, writer)
      # Schedule another compaction in case the generated file fills a level
      |> maybe_schedule_compactions()
      |> then(&{:noreply, &1})
    end
  end

  def handle_info({:DOWN, ref, _, _, :normal}, %__MODULE__{task: %Task{ref: ref}} = state) do
    {:noreply, %{state | task: nil, tmp: nil}}
  end

  def handle_info({:DOWN, ref, _, _, reason}, %__MODULE__{task: %Task{ref: ref}} = state) do
    Logger.error("Flushing memtable failed due to #{inspect(reason)}")

    {:stop, reason, %{state | task: nil, tmp: nil}}
  end

  @impl true
  def terminate(reason, %__MODULE__{task: task, writer: writer}) do
    case kill_pending_task(task, writer) do
      :ok ->
        Logger.info("Terminating writer process due to #{inspect(reason)}")

      {:error, reason} ->
        Logger.error(
          "Could not successfully terminate writer process because pending task failed due to #{inspect(reason)}"
        )
    end
  end

  defp maybe_schedule_compactions(%{writer: writer} = state) do
    writer
    |> Writer.manifest()
    |> Manifest.needs_compaction?()
    |> case do
      false -> state
      true -> schedule_compaction(state)
    end
  end

  defp schedule_compaction(%{writer: writer} = state) do
    with {:ok, compaction} <- Manifest.pick_compaction(writer.manifest),
         :ok <- CompactionController.process(compaction, writer.dir) do
      state
    else
      {:error, reason} when is_binary(reason) ->
        raise reason
    end
  end

  defp write_to_disk_if_needed(%{task: task, flush_fn: flush_fn, writer: writer} = state) do
    with true <- Writer.buffer_filled?(writer),
         nil <- task do
      writer
      |> flush_fn.()
      |> then(&%{state | task: &1, tmp: writer, writer: gen_new_space(writer)})
    else
      false ->
        state

      %Task{} = task ->
        Logger.info("Current memtable is full; waiting...")
        wait_for_task(task)
        write_to_disk_if_needed(%{state | tmp: nil, task: nil})
    end
  end

  defp gen_new_space(%{dir: dir, manifest: manifest} = writer) do
    number = Manifest.new_file_number(manifest)

    %{writer | wal: Wal.create(dir, number), mem_table: MemTable.new()}
  end

  defp wait_for_task(task) do
    with {:ok, file_meta} <- Task.yield(task),
         {:add_file, ^file_meta} <- send(self(), {:add_file, file_meta}) do
      :ok
    else
      {:exit, :normal} -> :ok
      nil -> wait_for_task(task)
    end
  end

  # Shutting down the pending task isn't terminal because data written will
  # be recovered when the writer is restarted and we can flush again.
  defp kill_pending_task(nil, _writer), do: :ok

  defp kill_pending_task(task, writer) do
    with {:ok, file_metas} <- Task.shutdown(task),
         {:ok, _writer} <- add_files_to_manifest(file_metas, writer) do
      :ok
    else
      nil -> :ok
      {:exit, :normal} -> :ok
      error -> error
    end
  end

  defp add_files_to_manifest(file_metas, writer) do
    # Only commit log number after successfully flushing the memtable to disk
    manifest = Writer.manifest(writer)

    changes =
      %Changes{}
      |> Changes.add_files(0, file_metas)
      |> Changes.set_log_number(manifest.log_number)

    with {:ok, manifest} <- Manifest.apply_and_log(manifest, changes) do
      {:ok, %{writer | manifest: manifest}}
    end
  end

  defp flush_async(%{
         dir: dir,
         manifest: manifest,
         mem_table: mem_table,
         options: options,
         wal: wal
       }) do
    fun = Manifest.new_file_number_fn(manifest)
    opts = [max_file_size: options.max_file_size]

    Task.Supervisor.async_nolink(BackgroundTaskSupervisor, fn ->
      # This steps should be encapsulated in the writer module but wasn't
      # because of data copying from this server to the task process so
      # we only handpick the data needed by this task process
      with {:ok, file_meta} <- SSTable.flush(mem_table, dir, fun, opts),
           :ok <- Wal.delete(wal) do
        file_meta
      end
    end)
  end

  defp publish_new_files!(index, files) do
    files
    |> Enum.sort_by(& &1.number)
    |> Enum.each(&(:ok = PubSub.publish(index, :file_created, &1)))
  end
end
