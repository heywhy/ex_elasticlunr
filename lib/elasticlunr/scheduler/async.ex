defmodule Elasticlunr.Scheduler.Async do
  use Elasticlunr.Scheduler
  use GenServer

  alias Elasticlunr.{Field, Index, Logger}
  alias Elasticlunr.{SchedulerRegistry, SchedulerSupervisor}
  alias Elasticlunr.Utils.Process

  @impl true
  def push(%Index{name: name} = index, action) do
    with :ok <- start_if_not_started(index) do
      via(name) |> GenServer.cast({action, index})
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  def start_link(%Index{name: name}) do
    GenServer.start_link(__MODULE__, blank_state(),
      name: via(name),
      hibernate_after: 5_000
    )
  end

  @spec child_spec(Index.t()) :: map()
  def child_spec(%Index{name: id} = index) do
    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [index]},
      restart: :transient
    }
  end

  @spec via(binary()) :: {:via, Registry, {SchedulerRegistry, atom()}}
  def via(name) do
    {:via, Registry, {SchedulerRegistry, name}}
  end

  @impl true
  def handle_cast({:calculate_idf, %Index{fields: fields, name: name}}, state) do
    start_time = :os.system_time(:millisecond)

    :ok = Enum.each(fields, fn {_, field} -> Field.calculate_idf(field) end)

    end_time = :os.system_time(:millisecond)

    Logger.debug("done calculating idf for index (#{name}) in #{end_time - start_time}ms")

    {:noreply, state}
  end

  defp blank_state, do: %{}

  defp start_if_not_started(%{name: name} = index) do
    with false <- loaded?(name),
         {:ok, _} <- start(index) do
      :ok
    else
      true -> :ok
      err -> err
    end
  end

  defp start(index) do
    DynamicSupervisor.start_child(SchedulerSupervisor, {__MODULE__, index})
  end

  defp loaded?(name) do
    loaded_indices()
    |> Enum.any?(fn
      ^name ->
        true

      _ ->
        false
    end)
  end

  defp loaded_indices do
    Process.active_processes(SchedulerSupervisor, SchedulerRegistry, __MODULE__)
  end
end
