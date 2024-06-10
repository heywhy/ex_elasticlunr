defmodule Elasticlunr.CompactionController do
  use GenServer

  alias Elasticlunr.Compaction

  defstruct [:task, compactions: []]

  @spec process(Compaction.t(), Path.t()) :: :ok
  def process(%Compaction{} = compaction, dir) do
    GenServer.call(__MODULE__, {:process, compaction, dir})
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__, hibernate_after: 5_000)
  end

  @impl true
  def init([]), do: {:ok, %__MODULE__{}}

  @impl true
  def handle_call(
        {:process, compaction, dir},
        {from, _tag},
        %__MODULE__{compactions: compactions, task: task} = state
      ) do
    compactions = [{compaction, dir, from}] ++ compactions

    task =
      case task do
        nil -> nil
        task -> task
      end

    {:reply, :ok, %{state | compactions: compactions, task: task}}
  end
end
