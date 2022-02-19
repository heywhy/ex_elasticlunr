defmodule Elasticlunr.IndexManager do
  alias Elasticlunr.{Dyno, Index, Storage}

  @spec preload() :: :ok
  def preload do
    Storage.all()
    |> Stream.each(&Dyno.start/1)
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
    with {:ok, _} <- Dyno.start(index),
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
  def remove(%Index{name: name} = index) do
    with :ok <- Dyno.stop(index),
         :ok <- Storage.delete(name) do
      :ok
    else
      {:error, :not_found} ->
        :not_running

      err ->
        err
    end
  end

  @spec loaded?(binary()) :: boolean()
  def loaded?(name) do
    Enum.any?(Dyno.running(), fn
      ^name ->
        true

      _ ->
        false
    end)
  end
end
