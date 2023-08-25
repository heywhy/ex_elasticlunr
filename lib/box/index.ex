defmodule Box.Index do
  use GenServer

  alias Box.MemTable
  alias Box.MemTable.Entry, as: MemTableEntry
  alias Box.Schema
  alias Box.Wal
  alias Elasticlunr.IndexRegistry

  defstruct [:dir, :schema, :wal, :mem_table]

  @type t :: %__MODULE__{
          wal: Wal.t(),
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

      @spec get(binary()) :: map() | nil
      def get(id), do: Index.get(@name, id)

      @spec save(map()) :: {:ok, map()}
      def save(document), do: Index.save(@name, document)

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

  @spec save(binary(), map()) :: {:ok, map()}
  def save(index, document), do: GenServer.call(via(index), {:save, document})

  @spec delete(binary(), binary()) :: :ok
  def delete(index, id), do: GenServer.call(via(index), {:delete, id})

  @spec get(binary(), binary()) :: map() | nil
  def get(index, id), do: GenServer.call(via(index), {:get, id})

  @spec running?(binary()) :: boolean()
  def running?(index) do
    case Registry.lookup(IndexRegistry, index) do
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

  require Logger

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

    {key, document} =
      document
      |> Map.take(known_fields)
      |> Map.pop_lazy(:id, &FlakeId.get/0)

    with timestamp <- :os.system_time(:millisecond),
         value <- :erlang.term_to_binary(document),
         mem_table <- MemTable.set(mem_table, key, value, timestamp),
         {:ok, wal} <- Wal.set(wal, key, value, timestamp),
         :ok <- Wal.flush(wal),
         document <- Map.put(document, :id, key),
         state <- %{state | wal: wal, mem_table: mem_table} do
      {:reply, {:ok, document}, write_to_disk_if_needed(state)}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:delete, key}, _from, %__MODULE__{wal: wal, mem_table: mem_table} = state) do
    with timestamp <- :os.system_time(:millisecond),
         mem_table <- MemTable.remove(mem_table, key, timestamp),
         {:ok, wal} <- Wal.remove(wal, key, timestamp),
         :ok <- Wal.flush(wal),
         state <- %{state | wal: wal, mem_table: mem_table} do
      {:reply, :ok, write_to_disk_if_needed(state)}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:get, key}, _from, %__MODULE__{mem_table: mem_table} = state) do
    with %MemTableEntry{value: value} <- MemTable.get(mem_table, key),
         value <- :erlang.binary_to_term(value),
         value <- Map.put(value, :id, key) do
      {:reply, value, state}
    end
  end

  @impl true
  def terminate(reason, %__MODULE__{wal: wal, schema: schema}) do
    :ok = Wal.close(wal)
    Logger.info("Terminating index #{schema.name} due to #{inspect(reason)}")
  end

  defp via(index), do: {:via, Registry, {IndexRegistry, index}}

  defp write_to_disk_if_needed(%__MODULE__{mem_table: mem_table} = state) do
    case MemTable.maxed?(mem_table) do
      false -> state
      true -> write_to_disk(state)
    end
  end

  defp write_to_disk(%__MODULE__{dir: dir, wal: wal, mem_table: mem_table} = state) do
    :ok = MemTable.flush(mem_table, dir)
    :ok = Wal.delete(wal)

    %{state | wal: Wal.create(dir), mem_table: MemTable.new()}
  end

  defp create_dir(dir) do
    case File.dir?(dir) do
      true -> :ok
      false -> File.mkdir_p(dir)
    end
  end
end
