defmodule Elasticlunr.Server.Writer do
  use GenServer

  alias Elasticlunr.BackgroundTaskSupervisor
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Index.Writer
  alias Elasticlunr.Manifest
  alias Elasticlunr.Manifest.Changes
  alias Elasticlunr.MemTable
  alias Elasticlunr.PubSub
  alias Elasticlunr.SSTable
  alias Elasticlunr.Wal

  require Logger

  defstruct [:task, :tmp, :flush_fn, :writer]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, [hibernate_after: 5_000] ++ opts)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    dir = Keyword.fetch!(opts, :dir)
    schema = Keyword.fetch!(opts, :schema)
    mt_max_size = Keyword.fetch!(opts, :mem_table_max_size)
    flush_fn = Keyword.get(opts, :flush_fn, &flush_async/1)

    dir
    |> Writer.new(schema, mt_max_size)
    |> Writer.recover()
    |> case do
      {:ok, writer} -> {:ok, %__MODULE__{flush_fn: flush_fn, writer: writer}}
      {:error, reason} -> {:stop, reason}
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
  def handle_info({ref, %FileMeta{} = file_meta}, %__MODULE__{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    case handle_info({:add_file, file_meta}, state) do
      {:noreply, state} -> {:noreply, %{state | task: nil, tmp: nil}}
      error -> error
    end
  end

  def handle_info({:add_file, file_meta}, %__MODULE__{writer: writer} = state) do
    %Writer{schema: schema} = writer
    manifest = Writer.manifest(writer)

    # Only commit log number after successfully flushing the memtable to disk
    changes =
      manifest.log_number
      |> Changes.set_log_number()
      |> Changes.add_file(file_meta)

    with {:ok, manifest} <- Manifest.apply_and_log(manifest, changes),
         :ok <- PubSub.publish(schema.name, :file_created, file_meta) do
      writer
      |> Map.put(:manifest, manifest)
      |> then(&{:noreply, %{state | writer: &1}})
    end
  end

  def handle_info({:DOWN, ref, _, _, reason}, %__MODULE__{task: %Task{ref: ref}} = state) do
    Logger.error("Flushing memtable failed due to #{inspect(reason)}")

    {:stop, reason, %{state | task: nil, tmp: nil}}
  end

  @impl true
  def terminate(reason, %__MODULE__{task: task, writer: writer}) do
    :ok = wait_for_task(task)
    :ok = Writer.close(writer)

    %Writer{schema: schema} = writer

    Logger.info("Terminating writer process for #{schema.name} due to #{inspect(reason)}")
  end

  defp write_to_disk_if_needed(%{task: task, flush_fn: flush_fn, writer: writer} = state) do
    with true <- Writer.buffer_filled?(writer),
         nil <- task,
         {task, writer} <- flush_fn.(writer) do
      %{state | task: task, tmp: writer, writer: gen_new_space(writer)}
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
    {number, manifest} = Manifest.new_file_number(manifest)
    %{writer | manifest: manifest, wal: Wal.create(dir, number), mem_table: MemTable.new()}
  end

  defp wait_for_task(nil), do: :ok

  defp wait_for_task(task) do
    with {:ok, file_meta} <- Task.yield(task) || Task.ignore(task),
         {:add_file, ^file_meta} <- send(self(), {:add_file, file_meta}) do
      :ok
    else
      {:exit, :normal} -> :ok
      nil -> wait_for_task(task)
    end
  end

  defp flush_async(%{dir: dir, manifest: manifest, mem_table: mem_table, wal: wal} = writer) do
    {file_number, manifest} = Manifest.new_file_number(manifest)
    file_meta = %FileMeta{dir: dir, number: file_number}

    # TODO: revisit this logic to either move it to writer module
    task =
      Task.Supervisor.async_nolink(BackgroundTaskSupervisor, fn ->
        # This steps should be encapsulated in the writer module but wasn't
        # because of data copying from this server to the task process
        with {:ok, file_meta} <- SSTable.flush(mem_table, file_meta),
             # TODO: remove wal from manifest
             :ok <- Wal.delete(wal),
             true <- file_meta.size > 0 do
          file_meta
        end
      end)

    {task, %{writer | manifest: manifest}}
  end
end
