defmodule Elasticlunr.Compaction do
  use GenServer

  defstruct [:strategy, :task, :watcher]

  @type t :: %__MODULE__{
          strategy: tuple(),
          task: nil | Task.t()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, hibernate_after: 5_000)
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end
end
