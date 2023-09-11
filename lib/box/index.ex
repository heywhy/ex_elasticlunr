defmodule Box.Index do
  use GenServer

  alias Box.MemTable
  alias Box.MemTable.Entry, as: MemTableEntry
  alias Box.Schema
  alias Box.Wal
  alias Box.Writer

  require Logger

  defstruct [:dir, :schema, :wal, :mem_table]

  @type t :: %__MODULE__{
          wal: Wal.t(),
          dir: Path.t(),
          schema: Schema.t(),
          mem_table: MemTable.t()
        }

  defmacro __using__(_opts) do
    quote do
      import Box.Schema

      @before_compile Box.Index

      @spec child_spec(keyword()) :: Supervisor.child_spec()
      def child_spec(arg) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [arg]}
        }
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      alias Box.Index
      alias Box.Schema

      fields = [:id] |> Enum.concat(Map.keys(@schema.fields)) |> Enum.uniq()

      defstruct fields

      @spec get(binary()) :: struct() | nil
      def get(id) do
        with %{} = document <- Index.get(@name, id) do
          struct!(__MODULE__, document)
        end
      end

      @spec save(struct()) :: {:ok, struct()}
      def save(%__MODULE__{} = document) do
        with document <- Map.from_struct(document),
             {:ok, document} <- Index.save(@name, document) do
          {:ok, struct!(__MODULE__, document)}
        end
      end

      @spec delete(binary()) :: :ok
      def delete(id), do: Index.delete(@name, id)

      @spec __schema__() :: Schema.t()
      def __schema__, do: @schema

      @spec running?() :: boolean()
      def running?, do: Index.running?(@name)

      @spec start_link(keyword()) :: GenServer.on_start()
      def start_link(_opts), do: Index.start_link(schema: @schema)
    end
  end

  @otp_app :elasticlunr
  @registry Elasticlunr.IndexRegistry

  @spec save(binary(), map()) :: {:ok, map()}
  def save(index, document), do: GenServer.call(via(index), {:save, document})

  @spec delete(binary(), binary()) :: :ok
  def delete(index, id), do: GenServer.call(via(index), {:delete, id})

  @spec get(binary(), binary()) :: map() | nil
  def get(index, id), do: GenServer.call(via(index), {:get, id})

  @spec running?(binary()) :: boolean()
  def running?(index) do
    case Registry.lookup(@registry, index) do
      [] -> false
      [{_pid, _config}] -> true
    end
  end

  @impl true
  def init(%Schema{} = schema) do
    Process.flag(:trap_exit, true)

    dir =
      @otp_app
      |> Application.fetch_env!(:storage_dir)
      |> Path.join(schema.name)
      |> Path.absname()

    with :ok <- create_dir(dir),
         {wal, mem_table} <- Wal.load_from_dir(dir) do
      opts = [
        dir: dir,
        wal: wal,
        schema: schema,
        mem_table: mem_table
      ]

      {:ok, struct!(__MODULE__, opts)}
    end
  end

  @spec start_link(schema: Schema.t()) :: GenServer.on_start()
  def start_link(schema: schema) do
    %Schema{name: name} = schema

    GenServer.start_link(__MODULE__, schema, name: via(name), hibernate_after: 5_000)
  end

  # Callbacks
  @impl true
  def handle_call(
        {:save, document},
        _from,
        %__MODULE__{schema: schema, wal: wal, mem_table: mem_table} = state
      ) do
    known_fields = Map.keys(schema.fields)

    {id, document} =
      document
      |> Map.take(known_fields)
      |> Map.replace_lazy(:id, fn
        nil -> FlakeId.get()
        value -> value
      end)
      |> Map.pop!(:id)

    with timestamp <- :os.system_time(:millisecond),
         value <- :erlang.term_to_binary(document),
         mem_table <- MemTable.set(mem_table, id, value, timestamp),
         {:ok, wal} <- Wal.set(wal, id, value, timestamp),
         :ok <- Wal.flush(wal),
         document <- Map.put(document, :id, id),
         state <- %{state | wal: wal, mem_table: mem_table} do
      {:reply, {:ok, document}, write_to_disk_if_needed(state)}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:delete, id}, _from, %__MODULE__{wal: wal, mem_table: mem_table} = state) do
    with timestamp <- :os.system_time(:millisecond),
         mem_table <- MemTable.remove(mem_table, id, timestamp),
         {:ok, wal} <- Wal.remove(wal, id, timestamp),
         :ok <- Wal.flush(wal),
         state <- %{state | wal: wal, mem_table: mem_table} do
      {:reply, :ok, write_to_disk_if_needed(state)}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:get, id}, _from, %__MODULE__{dir: dir, mem_table: mem_table} = state) do
    with %MemTableEntry{deleted: false, value: value} <- MemTable.get(mem_table, id, dir),
         value <- :erlang.binary_to_term(value),
         value <- Map.put(value, :id, id) do
      {:reply, value, state}
    else
      %MemTableEntry{deleted: true} -> {:reply, nil, state}
    end
  end

  @impl true
  def terminate(reason, %__MODULE__{wal: wal, schema: schema}) do
    :ok = Wal.close(wal)
    Logger.info("Terminating index #{schema.name} due to #{inspect(reason)}")
  end

  defp via(index), do: {:via, Registry, {@registry, index}}

  defp write_to_disk_if_needed(%__MODULE__{mem_table: mem_table} = state) do
    with true <- MemTable.maxed?(mem_table),
         false <- Writer.running?(state) do
      write_to_disk(state)
    else
      _ -> state
    end
  end

  defp write_to_disk(%__MODULE__{dir: dir, wal: wal, mem_table: mem_table} = state) do
    :ok = MemTable.flush(mem_table, dir)
    :ok = Wal.delete(wal)
    :ok = Writer.start(state)

    %{state | wal: Wal.create(dir), mem_table: MemTable.new()}
  end

  defp create_dir(dir) do
    case File.dir?(dir) do
      true -> :ok
      false -> File.mkdir_p(dir)
    end
  end
end
