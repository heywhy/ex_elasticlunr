defmodule Elasticlunr.Dyno do
  use GenServer

  alias Elasticlunr.{Index, IndexRegistry, IndexSupervisor}
  alias Elasticlunr.Utils.Process

  @spec get(String.t()) :: Index.t()
  def get(name) do
    GenServer.call(via(name), :get)
  end

  @spec update(Index.t()) :: Index.t()
  def update(%Index{name: name} = index) do
    GenServer.call(via(name), {:update, index})
  end

  @spec running :: [binary()]
  def running do
    Process.active_processes(IndexSupervisor, IndexRegistry, __MODULE__)
  end

  @spec start(Index.t()) :: {:ok, pid()} | {:error, any()}
  def start(index) do
    DynamicSupervisor.start_child(IndexSupervisor, {__MODULE__, index})
  end

  @spec stop(Index.t()) :: :ok | {:error, :not_found}
  def stop(%Index{name: name}) do
    with [{pid, _}] <- Registry.lookup(IndexRegistry, name),
         :ok <- DynamicSupervisor.terminate_child(IndexSupervisor, pid) do
      :ok
    else
      [] ->
        {:error, :not_found}

      err ->
        err
    end
  end

  @spec init(Index.t()) :: {:ok, map()}
  def init(%Index{} = index) do
    table = table_name(index)
    ^table = :ets.new(table, ~w[bag private compressed named_table]a)

    {:ok, %{index: index, table: table}}
  end

  def start_link(%Index{name: name} = index) do
    GenServer.start_link(__MODULE__, index, name: via(name), hibernate_after: 5_000)
  end

  @spec child_spec(Index.t()) :: map()
  def child_spec(%Index{name: id} = index) do
    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [index]},
      restart: :transient
    }
  end

  @spec via(binary()) :: {:via, Registry, {IndexRegistry, atom()}}
  def via(name) do
    {:via, Registry, {IndexRegistry, name}}
  end

  def handle_call(:get, _from, state) do
    {:reply, state[:index], state}
  end

  def handle_call({:update, index}, _from, state) do
    {:reply, index, %{state | index: index}}
  end

  defp table_name(%{name: name}), do: String.to_atom("elasticlunr_#{name}")
end
