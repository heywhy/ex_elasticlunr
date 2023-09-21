defmodule Box.Compaction do
  use GenServer

  alias Box.Fs
  alias Box.Schema

  require Logger

  defstruct [:dir, :schema, :watcher]

  @type t :: %__MODULE__{
          dir: Path.t(),
          watcher: pid(),
          schema: Schema.t()
        }

  @lockfile "c.lock"

  @spec unfinished?(Path.t()) :: boolean()
  def unfinished?(dir) do
    dir
    |> Path.join(@lockfile)
    |> File.exists?()
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, hibernate_after: 5_000)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with dir <- Keyword.fetch!(opts, :dir),
         watcher <- Fs.watch!(dir),
         schema <- Keyword.fetch!(opts, :schema),
         attrs <- [dir: dir, schema: schema, watcher: watcher] do
      {:ok, struct!(__MODULE__, attrs)}
    end
  end

  @impl true
  def handle_info(
        {:file_event, watcher, {path, events}},
        %__MODULE__{watcher: watcher} = state
      ) do
    Logger.debug("Received #{inspect(events)} for #{path}.")

    {:noreply, state}
  end

  def handle_info(
        {:file_event, watcher, :stop},
        %__MODULE__{dir: dir, watcher: watcher} = state
      ) do
    Logger.debug("Stop watching directory #{dir}.")

    {:noreply, state}
  end

  @impl true
  def terminate(reason, %__MODULE__{schema: schema}) do
    Logger.debug("Terminating compaction process for #{schema.name} due to #{inspect(reason)}")
  end
end
