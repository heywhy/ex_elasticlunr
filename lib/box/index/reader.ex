defmodule Box.Index.Reader do
  use GenServer

  alias Box.Index.Process
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
         watcher <- Process.fs_watcher(dir),
         :ok <- FileSystem.subscribe(watcher),
         attrs <- [dir: dir, watcher: watcher, segments: segments] do
      {:ok, struct!(__MODULE__, attrs)}
    end
  end

  # Callbacks
  @impl true
  def handle_call({:get, id}, _from, %__MODULE__{segments: segments} = state) do
    fun = fn ss_table, key, acc ->
      case SSTable.get(ss_table, key) do
        nil -> {:cont, acc}
        %Entry{} = entry -> {:halt, entry}
      end
    end

    result = Enum.reduce_while(segments, nil, &fun.(&1, id, &2))

    {:reply, result, state}
  end

  @impl true
  def handle_info(
        {:file_event, watcher, {path, events}},
        %__MODULE__{watcher: watcher, segments: segments} = state
      ) do
    with true <- SSTable.is?(path),
         :load <- action(events),
         nil <- Enum.find(segments, &(&1.path == path)),
         ss_table <- SSTable.from_file(path),
         segments <- Enum.concat([ss_table], segments) do
      Logger.debug("Update reader with #{path}.")
      {:noreply, %{state | segments: segments}}
    else
      false -> {:noreply, state}
      {_path, _ss_table} -> {:noreply, state}
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
    |> Enum.map(&SSTable.from_file/1)
  end
end
