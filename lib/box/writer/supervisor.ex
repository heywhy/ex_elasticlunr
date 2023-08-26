defmodule Box.Writer.Supervisor do
  use DynamicSupervisor

  alias Box.Index

  @spec running?(Index.t()) :: boolean()
  def running?(%Index{}) do
    DynamicSupervisor.which_children(__MODULE__)
    |> then(&(not Enum.empty?(&1)))
  end

  @spec start_child(Index.t()) :: :ok
  def start_child(%Index{}) do
    :ok
  end

  @impl true
  def init([]), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
end
