defmodule Elasticlunr.Dyno do
  use GenServer

  alias Elasticlunr.{Index, IndexRegistry, IndexSupervisor}
  alias Elasticlunr.Utils.Process

  @spec get(String.t()) :: Index.t()
  def get(name) do
    GenServer.call(via(name), :get)
  end

  @spec update(Index.t()) :: {:ok, Index.t()} | {:error, any()}
  def update(%Index{name: name} = index) do
    GenServer.call(via(name), {:update, index})
  end

  @spec running :: [binary()]
  def running do
    Process.active_processes(IndexSupervisor, IndexRegistry, __MODULE__)
  end

  @spec start(Index.t()) :: {:ok, pid()} | {:error, any()}
  def start(index) do
    # credo:disable-for-next-line
    with {:ok, _} <- DynamicSupervisor.start_child(IndexSupervisor, {__MODULE__, index}),
         {:ok, index} <- update(index) do
      {:ok, index}
    end
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

  @spec init(String.t()) :: {:ok, map()}
  def init(name) do
    table = String.to_atom("elasticlunr_#{name}")
    ^table = :ets.new(table, ~w[bag private compressed named_table]a)

    {:ok, %{index: nil, table: table}}
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, name, name: via(name), hibernate_after: 5_000)
  end

  @spec child_spec(Index.t()) :: map()
  def child_spec(%Index{name: id}) do
    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [id]},
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
    index = %{index | ops: []}
    {:reply, {:ok, index}, %{state | index: index}}
  end
end
