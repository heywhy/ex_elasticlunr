defmodule Elasticlunr.Index.Reader do
  use GenServer

  alias Elasticlunr.Fs
  alias Elasticlunr.Schema
  alias Elasticlunr.SSTable
  alias Elasticlunr.SSTable.Entry
  alias Elasticlunr.Utils

  require Logger

  defstruct [:dir, :schema, :segments, :watcher]

  @type t :: %__MODULE__{
          dir: Path.t(),
          watcher: pid(),
          schema: Schema.t(),
          segments: [SSTable.t()]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.validate!(opts, [:dir, :schema])

    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    with dir <- Keyword.fetch!(opts, :dir),
         schema <- Keyword.fetch!(opts, :schema),
         # TODO: pushing this action to handle_continue might improve performance
         segments <- load_segments(dir),
         watcher <- Fs.watch!(dir),
         attrs <- [dir: dir, schema: schema, watcher: watcher, segments: segments] do
      {:ok, struct!(__MODULE__, attrs)}
    end
  end

  # Callbacks
  @impl true
  def handle_call({:get, id}, _from, %__MODULE__{schema: schema, segments: segments} = state) do
    id = Utils.id_from_string(id)

    result =
      segments
      |> Enum.filter(&SSTable.contains?(&1, id))
      |> Task.async_stream(&SSTable.get(&1, id))
      |> Stream.map(fn {:ok, entry} -> entry end)
      # reject nil values in case of false positive by the bloom filter
      |> Stream.reject(&is_nil/1)
      |> Enum.max_by(& &1.timestamp, &Kernel.>=/2, fn -> nil end)
      |> case do
        nil -> nil
        %Entry{key: ^id, deleted: true} -> nil
        %Entry{key: ^id} = entry -> entry_to_document(entry, schema)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(
        {:file_event, watcher, {path, events}},
        %__MODULE__{watcher: watcher, segments: segments} = state
      ) do
    with true <- SSTable.lockfile?(path),
         :create <- Fs.event_to_action(events),
         path <- Path.dirname(path),
         nil <- Enum.find(segments, &(&1.path == path)),
         ss_table <- SSTable.from_path(path),
         segments <- Enum.concat([ss_table], segments) do
      Logger.debug("Update reader with #{path}.")
      {:noreply, %{state | segments: segments}}
    else
      false ->
        {:noreply, state}

      %SSTable{} ->
        {:noreply, state}

      :remove ->
        path = Path.dirname(path)
        segments = Enum.reject(segments, &(&1.path == path))

        {:noreply, %{state | segments: segments}}
    end
  end

  def handle_info(
        {:file_event, watcher, :stop},
        %__MODULE__{dir: dir, watcher: watcher} = state
      ) do
    Logger.debug("Stop watching directory #{dir}.")

    {:noreply, state}
  end

  defp load_segments(dir) do
    dir
    |> SSTable.list()
    |> Enum.map(&SSTable.from_path/1)
  end

  defp entry_to_document(%Entry{key: key, value: value}, schema) do
    schema
    |> Schema.binary_to_document(value)
    |> Map.put(:id, Utils.id_to_string(key))
  end
end
