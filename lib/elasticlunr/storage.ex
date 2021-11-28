defmodule Elasticlunr.Storage do
  alias Elasticlunr.Index

  @callback read(name :: Elasticlunr.index_name(), opts :: keyword()) :: Index.t()
  @callback write(index :: Index.t(), opts :: keyword()) :: :ok | {:error, any()}

  defmacro __using__(name) do
    quote bind_quoted: [name: name] do
      @behaviour Elasticlunr.Storage

      def config(opts, key, default \\ nil) do
        case Keyword.get(opts, key) do
          nil ->
            :elasticlunr
            |> Application.get_env(__MODULE__, [])
            |> Keyword.get(key, default)

          value ->
            value
        end
      end
    end
  end
end
