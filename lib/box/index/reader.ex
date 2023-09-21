defmodule Box.Index.Reader do
  use GenServer

  alias Box.Index.Fs
  alias Box.SSTable
  alias Box.SSTable.Entry

  require Logger

  defstruct [:dir, :segments, :watcher]

  @type t :: %__MODULE__{
          dir: Path.t(),
          watcher: pid(),
          segments: [SSTable.t()]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    with dir <- Keyword.fetch!(opts, :dir),
         # TODO: pushing this action to handle_continue might improve performance
         segments <- load_segments(dir),
         watcher <- Fs.watch!(dir),
         :ok <- FileSystem.subscribe(watcher),
         attrs <- [dir: dir, watcher: watcher, segments: segments] do
      {:ok, struct!(__MODULE__, attrs)}
    end
  end

  # Callbacks
  @impl true
  def handle_call({:get, id}, _from, %__MODULE__{segments: segments} = state) do
    fun = fn ss_table, key, acc ->
      with true <- SSTable.contains?(ss_table, key),
           %Entry{key: key} = entry <- SSTable.get(ss_table, key) do
        {:halt, %{entry | key: FlakeId.to_string(key)}}
      else
        _ -> {:cont, acc}
      end
    end

    id = FlakeId.from_string(id)
    result = Enum.reduce_while(segments, nil, &fun.(&1, id, &2))

    {:reply, result, state}
  end

  @impl true
  def handle_info(
        {:file_event, watcher, {path, events}},
        %__MODULE__{watcher: watcher, segments: segments} = state
      ) do
    with true <- SSTable.lockfile?(path),
         :load <- action(events),
         path <- Path.dirname(path),
         nil <- Enum.find(segments, &(&1.path == path)),
         ss_table <- SSTable.from_path(path),
         segments <- Enum.concat([ss_table], segments) do
      Logger.debug("Update reader with #{path}.")
      {:noreply, %{state | segments: segments}}
    else
      false -> {:noreply, state}
      %SSTable{} -> {:noreply, state}
      :remove -> {:noreply, %{state | segments: Enum.reject(segments, &(&1.path == path))}}
    end
  end

  def handle_info(
        {:file_event, watcher, :stop},
        %__MODULE__{dir: dir, watcher: watcher} = state
      ) do
    Logger.debug("Stop watching directory #{dir}.")

    {:noreply, state}
  end

  def handle_info({:file_event, _watcher, _arg}, %__MODULE__{} = state), do: {:noreply, state}

  defp action(events) do
    case :removed in events or :deleted in events do
      false -> :load
      true -> :remove
    end
  end

  defp load_segments(dir) do
    dir
    |> SSTable.list()
    # Reverse list so that we have the latest segment at the top
    |> Enum.reverse()
    |> Enum.map(&SSTable.from_path/1)
  end
end
