defmodule Box.Compaction.Supervisor do
  use Supervisor

  @impl true
  def init([]) do
    children = [
      {Registry, name: Elasticlunr.CompactionRegistry, keys: :unique},
      {DynamicSupervisor, name: Elasticlunr.CompactionSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)
end
