defmodule Elasticlunr.Index.Supervisor do
  use Supervisor

  alias Elasticlunr.Fs
  alias Elasticlunr.Process
  alias Elasticlunr.Schema
  alias Elasticlunr.Server.Reader
  alias Elasticlunr.Server.Writer

  @otp_app :elasticlunr
  # default to 160mb
  @mem_table_max_size 167_772_160
  @registry Elasticlunr.IndexRegistry

  @spec save(binary(), map()) :: map()
  def save(index, document) do
    index
    |> Process.writer()
    |> GenServer.call({:save, document})
  end

  @spec save_all(binary(), [map()], :infinity | non_neg_integer()) :: :ok
  def save_all(index, documents, timeout \\ :infinity) do
    index
    |> Process.writer()
    |> GenServer.call({:save_all, documents}, timeout)
  end

  @spec delete(binary(), binary()) :: :ok
  def delete(index, id) do
    index
    |> Process.writer()
    |> GenServer.call({:delete, id})
  end

  @spec get(binary(), binary()) :: map() | nil
  def get(index, id) do
    with writer_pid <- Process.writer(index),
         nil <- GenServer.call(writer_pid, {:get, id}),
         reader_pid <- Process.reader(index) do
      GenServer.call(reader_pid, {:get, id})
    end
  end

  @spec running?(binary()) :: boolean()
  def running?(index) do
    @registry
    |> Registry.lookup(index)
    |> then(&match?([{_pid, _config}], &1))
  end

  @spec start_link(schema: Schema.t()) :: Supervisor.on_start()
  def start_link(schema: schema) do
    %Schema{name: name} = schema

    Supervisor.start_link(__MODULE__, schema, name: via(name))
  end

  @impl true
  def init(%Schema{compaction_strategy: compaction} = schema) do
    dir = create_dir!(schema)
    {strategy, opts} = compaction
    mem_table_max_size = Application.get_env(@otp_app, :mem_table_max_size, @mem_table_max_size)

    children = [
      {Fs, dir},
      {strategy, [dir: dir, schema: schema] ++ opts},
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
