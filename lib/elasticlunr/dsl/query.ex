defmodule Elasticlunr.Dsl.Query do
  @moduledoc false

  alias Elasticlunr.{Index, Dsl.QueryRepository}

  @type score_results ::
          list(%{
            score: integer(),
            ref: Index.document_ref()
          })

  @type options :: any()

  @callback filter(module :: struct(), index :: Index.t()) :: struct()
  @callback score(module :: struct(), index :: Index.t()) :: score_results()
  @callback rewrite(module :: struct(), index :: Index.t()) :: struct()
  @callback parse(options :: keyword(), query_options :: keyword(), repo :: module()) :: score_results()

  @spec split_root(list()) :: {atom(), any()}
  def split_root(root) when is_list(root), do: hd(root)

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Elasticlunr.Dsl.Query

      if not function_exported?(__MODULE__, :filter, 2) do
        def filter(query, index) do
          query
          |> QueryRepository.score(index)
          |> Enum.filter(&(&1.score > 0))
        end
      end

      if not function_exported?(__MODULE__, :rewrite, 2) do
        def rewrite(query, _index), do: query
      end
    end
  end
end
