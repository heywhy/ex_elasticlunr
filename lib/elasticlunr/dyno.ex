defmodule Elasticlunr.Dyno do
  @moduledoc false
  use GenServer

  alias Elasticlunr.{Index, IndexRegistry}

  @spec get(String.t()) :: Index.t()
  def get(name) do
    GenServer.call(via(name), :get)
  end

  @spec update(Index.t()) :: Index.t()
  def update(%Index{name: name} = index) do
    GenServer.call(via(name), {:update, index})
  end

  @spec init(Index.t()) :: {:ok, Index.t()}
  def init(%Index{} = index) do
    {:ok, index}
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

  def handle_call(:get, _from, index) do
    {:reply, index, index}
  end

  def handle_call({:update, index}, _from, _state) do
    {:reply, index, index}
  end
end
