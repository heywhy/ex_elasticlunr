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
    case running?(name) do
      true -> Dyno.get(name)
      false -> :not_running
    end
  end

  @spec save(Index.t()) :: {:ok, Index.t()} | {:error, any()}
  def save(%Index{name: name} = index) do
    persist_fn =
      case running?(name) do
        false ->
          &Dyno.start/1

        true ->
          &Dyno.update/1
      end

    with {:ok, index} <- persist_fn.(index),
         :ok <- Storage.write(index) do
      {:ok, index}
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

  @spec running?(binary()) :: boolean()
  def running?(name) do
    Enum.any?(Dyno.running(), fn
      ^name ->
        true

      _ ->
        false
    end)
  end
end
