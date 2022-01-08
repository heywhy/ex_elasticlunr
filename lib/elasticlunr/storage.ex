defmodule Elasticlunr.Storage do
  alias Elasticlunr.Index
  alias Elasticlunr.Storage.Blackhole

  @spec all() :: list(Index.t())
  def all do
    provider().load_all()
  end

  @spec write(Index.t()) :: :ok | {:error, any()}
  def write(%Index{} = index) do
    provider().write(index)
  end

  @spec read(binary()) :: Index.t() | {:error, any()}
  def read(index_name) do
    provider().read(index_name)
  end

  @spec delete(binary()) :: :ok | {:error, any()}
  def delete(index_name) do
    provider().delete(index_name)
  end

  defp provider, do: Application.get_env(:elasticlunr, :storage, Blackhole)

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Elasticlunr.Storage.Provider

      defp config(key, default \\ nil) do
        :elasticlunr
        |> Application.get_env(__MODULE__, [])
        |> Keyword.get(key, default)
      end
    end
  end
end
