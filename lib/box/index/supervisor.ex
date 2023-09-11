defmodule Box.Index.Supervisor do
  use Supervisor

  alias Box.Compaction
  alias Box.Index.Writer
  alias Box.Schema

  @otp_app :elasticlunr
  @registry Elasticlunr.IndexRegistry

  @spec save(binary(), map()) :: {:ok, map()} | {:error, :not_running}
  def save(index, document) do
    case writer(index) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:save, document})
    end
  end

  @spec delete(binary(), binary()) :: :ok
  def delete(index, id) do
    case writer(index) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:delete, id})
    end
  end

  @spec get(binary(), binary()) :: map() | nil
  def get(index, id) do
    case writer(index) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:get, id})
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
    opts = [dir: dir, schema: schema]

    children = [
      {Compaction, opts},
      {Writer, opts}
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

  defp writer(index) do
    via(index)
    |> Supervisor.which_children()
    |> Enum.find(&(elem(&1, 0) == Writer))
    |> case do
      nil -> {:error, :not_found}
      {Writer, pid, :worker, [Writer]} -> pid
    end
  end
end
