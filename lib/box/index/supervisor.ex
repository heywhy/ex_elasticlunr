defmodule Box.Index.Supervisor do
  use Supervisor

  alias Box.Compaction
  alias Box.Index.Fs
  alias Box.Index.Process
  alias Box.Index.Reader
  alias Box.Index.Writer
  alias Box.Schema

  @otp_app :elasticlunr
  # default to 160mb
  @mem_table_max_size 167_772_160
  @registry Elasticlunr.IndexRegistry

  @spec save(binary(), map()) :: {:ok, map()} | {:error, :not_running}
  def save(index, document) do
    case Process.writer(index) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:save, document})
    end
  end

  @spec save_all(binary(), [map()]) :: :ok | {:error, :not_running}
  def save_all(index, documents) do
    case Process.writer(index) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:save_all, documents}, :infinity)
    end
  end

  @spec delete(binary(), binary()) :: :ok | {:error, :not_running}
  def delete(index, id) do
    case Process.writer(index) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:delete, id})
    end
  end

  @spec get(binary(), binary()) :: map() | nil | no_return()
  def get(index, id) do
    with writer_pid <- Process.writer(index),
         nil <- GenServer.call(writer_pid, {:get, id}),
         reader_pid <- Process.reader(index) do
      GenServer.call(reader_pid, {:get, id})
    end
  end

  @spec running?(binary()) :: boolean()
  def running?(index) do
    case Registry.lookup(@registry, index) do
      [] -> false
      [{_pid, _config}] -> true
    end
  end

  @spec start_link(schema: Schema.t()) :: Supervisor.on_start()
  def start_link(schema: schema) do
    %Schema{name: name} = schema

    Supervisor.start_link(__MODULE__, schema, name: via(name))
  end

  @impl true
  def init(%Schema{} = schema) do
    dir = create_dir!(schema)
    mem_table_max_size = Application.get_env(@otp_app, :mem_table_max_size, @mem_table_max_size)

    children = [
      {Fs, dir},
      {Compaction, dir: dir, schema: schema},
      {Writer, [dir: dir, schema: schema, mem_table_max_size: mem_table_max_size]},
      {Reader, dir: dir, schema: schema}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp via(index), do: {:via, Registry, {@registry, index}}

  defp create_dir!(schema) do
    dir =
      @otp_app
      |> Application.fetch_env!(:storage_dir)
      |> Path.join(schema.name)
      |> Path.absname()

    with false <- File.dir?(dir),
         :ok <- File.mkdir_p!(dir) do
      dir
    else
      true -> dir
    end
  end
end
