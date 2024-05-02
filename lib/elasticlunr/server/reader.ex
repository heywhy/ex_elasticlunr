defmodule Elasticlunr.Server.Reader do
  use GenServer
  use Rop

  alias Elasticlunr.FileMeta
  alias Elasticlunr.Filename
  alias Elasticlunr.Fs
  alias Elasticlunr.Index.Reader
  alias Elasticlunr.Manifest
  alias Elasticlunr.PubSub
  alias Elasticlunr.SSTable

  require Logger

  defstruct [:reader, :watcher]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.validate!(opts, [:dir, :schema])

    GenServer.start_link(__MODULE__, [hibernate_after: 5_000] ++ opts)
  end

  @impl true
  def init(opts) do
    dir = Keyword.fetch!(opts, :dir)
    schema = Keyword.fetch!(opts, :schema)

    :ok = PubSub.subscribe(schema.name)

    read_manifest(%{dir: dir, schema: schema}) >>>
      load_ss_tables() >>>
      patch_reader()
    |> case do
      {:error, reason} -> {:stop, reason}
      {:ok, reader} -> {:ok, %__MODULE__{reader: reader}}
    end
  end

  # Callbacks
  @impl true
  def handle_call({:get, id}, from, %__MODULE__{reader: reader} = state) do
    # Allow concurrent reads so that reads from
    # multiple processes don't block each other
    Task.async(fn ->
      reader
      |> Reader.get!(id)
      |> then(&GenServer.reply(from, &1))
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:file_created, %FileMeta{dir: dir, number: number} = file_meta},
        %__MODULE__{reader: reader} = state
      ) do
    file = Filename.ss_table(dir, number)

    with true <- File.exists?(file),
         {:ok, reader} <- Reader.add_segment(reader, file_meta) do
      Logger.debug("Update reader with #{file}.")
      {:noreply, %{state | reader: reader}}
    else
      v when is_boolean(v) -> {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp read_manifest(%{dir: dir} = state) do
    path = Filename.current(dir)

    with {:ok, content} <- File.read(path),
         manifest_path = Path.join(dir, content),
         {:ok, manifest} <- Manifest.from_path(manifest_path) do
      {:ok, Map.put(state, :manifest, manifest)}
    end
  end

  # INFO: pushing this action to handle_continue might improve performance
  defp load_ss_tables(%{dir: dir, manifest: manifest} = state) do
    known_files = Manifest.known_files(manifest)

    dir
    |> Fs.db_files()
    |> Enum.reduce_while([], fn path, acc ->
      with {:sst, number} <- Filename.parse(path),
           true <- MapSet.member?(known_files, number),
           %FileMeta{} = file_meta <- Manifest.find_file(manifest, number),
           {:ok, ss_table} <- SSTable.from_path(%{file_meta | dir: dir}) do
        {:cont, [ss_table] ++ acc}
      else
        {:error, _reason} = error -> {:halt, error}
        _ -> {:cont, acc}
      end
    end)
    |> case do
      ss_tables when is_list(ss_tables) ->
        state
        |> Map.put(:ss_tables, ss_tables)
        |> then(&{:ok, &1})

      error ->
        error
    end
  end

  defp patch_reader(%{dir: dir, manifest: manifest, schema: schema, ss_tables: segments}) do
    with :ok <- Manifest.close(manifest) do
      {:ok, Reader.new(dir, schema, segments: segments)}
    end
  end
end
