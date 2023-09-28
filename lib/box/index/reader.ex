defmodule Box.Index.Reader do
  use GenServer

  alias Box.Fs
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
        %Entry{key: key} = entry -> {:halt, %{entry | key: FlakeId.to_string(key)}}
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
         :create <- Fs.event_to_action(events),
         path <- Path.dirname(path),
         nil <- Enum.find(segments, &(&1.path == path)),
         ss_table <- SSTable.from_path(path),
         segments <- Enum.concat([ss_table], segments),
         segments <- Enum.sort_by(segments, & &1.path, :desc) do
      Logger.debug("Update reader with #{path}.")
      {:noreply, %{state | segments: segments}}
    else
      false ->
        {:noreply, state}

      %SSTable{} ->
        {:noreply, state}

      :remove ->
        path = Path.dirname(path)

        segments =
          segments
          |> Enum.reject(&(&1.path == path))
          |> Enum.sort_by(& &1.path, :desc)

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
    # Reverse list so that we have the latest segment at the top
    |> Enum.reverse()
    |> Enum.map(&SSTable.from_path/1)
  end
end
