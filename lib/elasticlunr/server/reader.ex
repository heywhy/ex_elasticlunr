defmodule Elasticlunr.Server.Reader do
  use GenServer

  alias Elasticlunr.Fs
  alias Elasticlunr.Index.Reader

  require Logger

  defstruct [:reader, :watcher]

  @type t :: %__MODULE__{
          reader: Reader.t(),
          watcher: pid()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.validate!(opts, [:dir, :schema])

    GenServer.start_link(__MODULE__, [hibernate_after: 5_000] ++ opts)
  end

  @impl true
  def init(opts) do
    with dir <- Keyword.fetch!(opts, :dir),
         schema <- Keyword.fetch!(opts, :schema),
         # TODO: pushing this action to handle_continue might improve performance
         segments <- Reader.load_segments(dir),
         watcher <- Fs.watch!(dir),
         reader <- Reader.new(dir, schema, segments: segments) do
      {:ok, %__MODULE__{reader: reader, watcher: watcher}}
    end
  end

  # Callbacks
  @impl true
  def handle_call({:get, id}, _from, %__MODULE__{reader: reader} = state) do
    result = Reader.get(reader, id)

    {:reply, result, state}
  end

  @impl true
  def handle_info(
        {:file_event, watcher, {path, events}},
        %__MODULE__{watcher: watcher, reader: reader} = state
      ) do
    with true <- Reader.lockfile?(path),
         :create <- Fs.event_to_action(events),
         path <- Path.dirname(path),
         reader <- Reader.add_segment(reader, path) do
      Logger.debug("Update reader with #{path}.")
      {:noreply, %{state | reader: reader}}
    else
      false ->
        {:noreply, state}

      :remove ->
        path = Path.dirname(path)

        {:noreply, %{state | reader: Reader.remove_segment(reader, path)}}
    end
  end

  def handle_info(
        {:file_event, watcher, :stop},
        %__MODULE__{watcher: watcher, reader: reader} = state
      ) do
    Logger.debug("Stop watching directory #{reader.dir}.")

    {:noreply, state}
  end
end
