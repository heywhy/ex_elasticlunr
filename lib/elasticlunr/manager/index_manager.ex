defmodule Elasticlunr.IndexManager do
  alias Elasticlunr.{Dyno, Index, IndexRegistry, IndexSupervisor, Storage}
  alias Elasticlunr.Utils.Process

  @spec preload() :: :ok
  def preload do
    Storage.all()
    |> Stream.each(&start/1)
    |> Stream.run()
  end

  @spec get(binary()) :: Index.t() | :not_running
  def get(name) do
    case loaded?(name) do
      true -> Dyno.get(name)
      false -> :not_running
    end
  end

  @spec save(Index.t()) :: {:ok, Index.t()} | {:error, any()}
  def save(%Index{} = index) do
    with {:ok, _} <- start(index),
         :ok <- Storage.write(index) do
      {:ok, index}
    end
  end

  @spec update(Index.t()) :: Index.t() | :not_running
  def update(%Index{name: name} = index) do
    with true <- loaded?(name),
         index <- Dyno.update(index),
         :ok <- Storage.write(index) do
      index
    else
      false ->
        :not_running

      err ->
        err
    end
  end

  @spec remove(Index.t()) :: :ok | :not_running
  def remove(%Index{name: name}) do
    with [{pid, _}] <- Registry.lookup(IndexRegistry, name),
         :ok <- Storage.delete(name),
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
    Process.active_processes(IndexSupervisor, IndexRegistry, Dyno)
  end

  defp start(index) do
    DynamicSupervisor.start_child(IndexSupervisor, {Dyno, index})
  end
end
