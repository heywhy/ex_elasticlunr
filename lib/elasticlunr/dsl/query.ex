defmodule Elasticlunr.Dsl.Query do
  @moduledoc false

  alias Elasticlunr.{Index, Dsl.QueryRepository}

  @type score_results ::
          list(%{
            score: integer(),
            ref: Index.document_ref()
          })

  @type options :: any()

  @callback filter(module :: struct(), index :: Index.t(), options :: options()) :: struct()
  @callback score(module :: struct(), index :: Index.t(), options :: options()) :: score_results()
  @callback rewrite(module :: struct(), index :: Index.t()) :: struct()
  @callback parse(options :: keyword(), query_options :: keyword(), repo :: module()) ::
              struct()

  @spec split_root(list()) :: {atom(), any()}
  def split_root(root) when is_list(root), do: hd(root)

  defmacro __using__(_) do
    quote location: :keep do
      @before_compile Elasticlunr.Dsl.Query
      @behaviour Elasticlunr.Dsl.Query
    end
  end

  defmacro __before_compile__(_) do
    mod = __CALLER__.module

    quote bind_quoted: [mod: mod] do
      if not Module.defines?(mod, {:filter, 2}) do
        def filter(query, index, options) do
          query
          |> QueryRepository.score(index, options)
          |> Enum.filter(&(&1.score > 0))
        end
      end

      if not Module.defines?(mod, {:rewrite, 2}) do
        def rewrite(query, _index), do: query
      end
    end
  end
end
