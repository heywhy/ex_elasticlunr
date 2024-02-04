defmodule Elasticlunr.Server.Writer do
  use GenServer

  alias Elasticlunr.{FlushMemTableSupervisor, SSTable, Wal}
  alias Elasticlunr.Index.Writer

  require Logger

  defstruct [:task, :tmp, :writer]

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

    writer = Writer.new(dir, schema, mt_max_size)

    {:ok, %__MODULE__{writer: writer}}
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
  def handle_info({ref, :ok}, %__MODULE__{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    {:noreply, %{state | task: nil, tmp: nil}}
  end

  def handle_info({:DOWN, ref, _, _, reason}, %__MODULE__{task: %Task{ref: ref}} = state) do
    Logger.error("Flushing memtable failed due to #{inspect(reason)}")

    {:noreply, %{state | task: nil, tmp: nil}}
  end

  def handle_info({:EXIT, pid, reason}, %__MODULE__{task: %Task{pid: pid}} = state) do
    # TODO: consider blocking writes if task fails due to error
    case reason do
      :normal -> {:noreply, %{state | task: nil, tmp: nil}}
      reason -> {:stop, reason, state}
    end
  end

  def handle_info({:EXIT, _pid, _reason}, %__MODULE__{} = state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %__MODULE__{task: task, writer: writer}) do
    :ok = wait_for_task(task)
    :ok = Writer.close(writer)

    %Writer{schema: schema} = writer

    Logger.info("Terminating writer process for #{schema.name} due to #{inspect(reason)}")
  end

  defp write_to_disk_if_needed(%{task: task, writer: writer} = state) do
    with true <- Writer.buffer_filled?(writer),
         nil <- task,
         task <- flush_async(writer) do
      %{state | task: task, tmp: writer, writer: Writer.clone(writer)}
    else
      false ->
        state

      %Task{} = task ->
        Logger.info("Current memtable is full; waiting...")
        wait_for_task(task)
        write_to_disk_if_needed(%{state | tmp: nil, task: nil})
    end
  end

  def wait_for_task(nil), do: :ok

  def wait_for_task(task) do
    case Task.yield(task) || Task.ignore(task) do
      {:ok, _} -> :ok
      nil -> wait_for_task(task)
    end
  end

  defp flush_async(%{dir: dir, mem_table: mem_table, wal: wal}) do
    Task.Supervisor.async(FlushMemTableSupervisor, fn ->
      # This steps should be encapsulate in the writer module but wasn't
      # because of data copying from this server to the task process
      _path = SSTable.flush(mem_table, dir)
      :ok = Wal.delete(wal)
    end)
  end

end
