defmodule Box.Index.Writer do
  use GenServer

  alias Box.MemTable
  alias Box.MemTable.Entry
  alias Box.Schema
  alias Box.SSTable
  alias Box.Wal

  require Logger

  defstruct [:dir, :schema, :wal, :mem_table, :mt_max_size]

  @type t :: %__MODULE__{
          wal: Wal.t(),
          dir: Path.t(),
          schema: Schema.t(),
          mem_table: MemTable.t(),
          mt_max_size: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    dir = Keyword.fetch!(opts, :dir)
    schema = Keyword.fetch!(opts, :schema)
    mt_max_size = Keyword.fetch!(opts, :mem_table_max_size)

    {wal, mem_table} = Wal.load_from_dir(opts[:dir])

    attrs = [
      dir: dir,
      wal: wal,
      schema: schema,
      mem_table: mem_table,
      mt_max_size: mt_max_size
    ]

    {:ok, struct!(__MODULE__, attrs)}
  end

  # Callbacks
  @impl true
  def handle_call({:save, document}, _from, %__MODULE__{schema: schema} = state) do
    with known_fields <- Map.keys(schema.fields),
         {document, state} <- save_document(document, known_fields, state),
         :ok <- Wal.flush(state.wal) do
      {:reply, {:ok, document}, write_to_disk_if_needed(state)}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:save_all, documents}, _from, %__MODULE__{} = state) do
    with state <- save_all(documents, state),
         :ok <- Wal.flush(state.wal) do
      {:reply, :ok, write_to_disk_if_needed(state)}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:delete, id}, _from, %__MODULE__{wal: wal, mem_table: mem_table} = state) do
    with id <- FlakeId.from_string(id),
         timestamp <- System.system_time(:microsecond),
         mem_table <- MemTable.remove(mem_table, id, timestamp),
         {:ok, wal} <- Wal.remove(wal, id, timestamp),
         :ok <- Wal.flush(wal),
         state <- %{state | wal: wal, mem_table: mem_table} do
      {:reply, :ok, write_to_disk_if_needed(state)}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:get, id}, _from, %__MODULE__{mem_table: mem_table} = state) do
    with id <- FlakeId.from_string(id),
         %Entry{deleted: false, value: value} <- MemTable.get(mem_table, id),
         value <- :erlang.binary_to_term(value),
         value <- Map.put(value, :id, FlakeId.to_string(id)) do
      {:reply, value, state}
    else
      %Entry{deleted: true} -> {:reply, nil, state}
      nil -> {:reply, nil, state}
    end
  end

  @impl true
  def terminate(reason, %__MODULE__{wal: wal, schema: schema}) do
    :ok = Wal.close(wal)

    Logger.info("Terminating writer process for #{schema.name} due to #{inspect(reason)}")
  end

  defp save_all(documents, %{schema: schema} = state) do
    known_fields = Map.keys(schema.fields)

    Enum.reduce(documents, state, fn document, state ->
      {_document, state} = save_document(document, known_fields, state)
      state
    end)
  end

  defp save_document(document, known_fields, state) do
    {id, document} =
      document
      |> Map.take(known_fields)
      |> Map.replace_lazy(:id, fn
        nil -> FlakeId.get() |> FlakeId.from_string()
        value -> FlakeId.from_string(value)
      end)
      |> Map.pop!(:id)

    with timestamp <- System.system_time(:microsecond),
         value <- :erlang.term_to_binary(document),
         mem_table <- MemTable.set(state.mem_table, id, value, timestamp),
         {:ok, wal} <- Wal.set(state.wal, id, value, timestamp),
         document <- Map.put(document, :id, FlakeId.to_string(id)) do
      {document, %{state | wal: wal, mem_table: mem_table}}
    end
  end

  defp write_to_disk_if_needed(
         %__MODULE__{dir: dir, wal: wal, mem_table: mem_table, mt_max_size: mt_max_size} =
           state
       ) do
    with true <- MemTable.size(mem_table) >= mt_max_size,
         _path <- SSTable.flush(mem_table, dir),
         :ok <- Wal.delete(wal) do
      %{state | wal: Wal.create(dir), mem_table: MemTable.new()}
    else
      false -> state
    end
  end
end
