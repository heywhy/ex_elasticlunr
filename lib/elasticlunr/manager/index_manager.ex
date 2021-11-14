defmodule Elasticlunr.IndexManager do
  use GenServer

  alias Elasticlunr.{Index, IndexRegistry, IndexSupervisor}
  alias Elasticlunr.Utils.Process

  @type index_name :: atom() | binary()

  @spec get(index_name()) :: Index.t() | :not_running
  def get(name) do
    case loaded?(name) do
      true -> name |> via |> GenServer.call(:get)
      false -> :not_running
    end
  end

  @spec load_index(Index.t()) :: {:ok, Index.t()}
  def load_index(%Index{} = index) do
    {:ok, _} = DynamicSupervisor.start_child(IndexSupervisor, {__MODULE__, index})
    {:ok, index}
  end

  @spec update_index(Elasticlunr.Index.t()) :: Index.t() | :not_running
  def update_index(%Index{name: name} = index) do
    case loaded?(name) do
      true ->
        name |> via |> GenServer.call({:update, index})

      false ->
        :not_running
    end
  end

  @spec loaded?(index_name()) :: boolean()
  def loaded?(name) do
    loaded_indices()
    |> Enum.any?(fn
      ^name ->
        true

      _ ->
        false
    end)
  end

  @spec loaded_indices :: [index_name()]
  def loaded_indices do
    Process.active_processes(IndexSupervisor, IndexRegistry, __MODULE__)
  end

  @spec init(Index.t()) :: {:ok, Index.t()}
  def init(%Index{} = index) do
    {:ok, index}
  end

  @spec start_link(Elasticlunr.Index.t()) :: :ignore | {:error, any} | {:ok, pid}
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

  @spec via(index_name()) :: {:via, Registry, {Elasticlunr.IndexRegistry, atom()}}
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
