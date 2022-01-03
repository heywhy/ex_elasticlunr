defmodule Elasticlunr.IndexManager do
  use GenServer

  alias Elasticlunr.{Index, IndexRegistry, IndexSupervisor}
  alias Elasticlunr.Utils.Process

  @spec get(binary()) :: Index.t() | :not_running
  def get(name) do
    case loaded?(name) do
      true -> name |> via |> GenServer.call(:get)
      false -> :not_running
    end
  end

  @spec save(Index.t()) :: {:ok, Index.t()} | {:already_started, pid()}
  def save(%Index{} = index) do
    case DynamicSupervisor.start_child(IndexSupervisor, {__MODULE__, index}) do
      {:ok, _} ->
        {:ok, index}

      {:error, reason} ->
        reason
    end
  end

  @spec update(Index.t()) :: Index.t() | :not_running
  def update(%Index{name: name} = index) do
    case loaded?(name) do
      true ->
        name |> via |> GenServer.call({:update, index})

      false ->
        :not_running
    end
  end

  @spec remove(Index.t()) :: :ok | :not_running
  def remove(%Index{name: name}) do
    with [{pid, _}] <- Registry.lookup(IndexRegistry, name),
         :ok <- DynamicSupervisor.terminate_child(IndexSupervisor, pid) do
      :ok
    else
      _ ->
        :not_running
    end
  end

  @spec loaded?(binary()) :: boolean()
  def loaded?(name) do
    loaded_indices()
    |> Enum.any?(fn
      ^name ->
        true

      _ ->
        false
    end)
  end

  @spec loaded_indices :: [binary()]
  def loaded_indices do
    Process.active_processes(IndexSupervisor, IndexRegistry, __MODULE__)
  end

  @spec init(Index.t()) :: {:ok, Index.t()}
  def init(%Index{} = index) do
    {:ok, index}
  end

  @spec start_link(Index.t()) :: :ignore | {:error, any} | {:ok, pid}
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

  @spec via(binary()) :: {:via, Registry, {Elasticlunr.IndexRegistry, atom()}}
  def via(name) do
    {:via, Registry, {IndexRegistry, name}}
  end

  def handle_call(:get, _from, index) do
    {:reply, index, index}
  end

  def handle_call({:update, index}, _from, _state) do
    {:reply, index, index}
  end
end
