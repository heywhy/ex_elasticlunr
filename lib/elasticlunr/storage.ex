defmodule Elasticlunr.Storage do
  alias Elasticlunr.Index

  @callback read(name :: Elasticlunr.index_name()) :: Index.t()
  @callback write(name :: Elasticlunr.index_name(), index :: Index.t()) :: :ok | {:error, any()}

  defmacro __using__(name) do
    quote bind_quoted: [name: name] do
      @behaviour Elasticlunr.Storage

      def config(key, default \\ nil) do
        :elasticlunr
        |> Application.get_env(unquote(name), [])
        |> Keyword.get(key, default)
      end
    end
  end
end
