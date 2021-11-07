defmodule Elasticlunr.Dsl.Query do
  alias Elasticlunr.{Index, Dsl.QueryRepository}

  @type score_results ::
          list(%{
            score: integer(),
            ref: Index.document_ref()
          })

  @type options :: map()

  @callback filter(module :: struct(), index :: Index.t(), options :: options()) :: list()
  @callback score(module :: struct(), index :: Index.t(), options :: options()) :: score_results()
  @callback rewrite(module :: struct(), index :: Index.t()) :: struct()
  @callback parse(options :: map(), query_options :: map(), repo :: module()) ::
              struct()

  @spec split_root(map() | tuple()) :: {atom(), any()}
  def split_root(root) when is_map(root) do
    [root_key] = Map.keys(root)
    value = Map.get(root, root_key)

    {root_key, value}
  end

  def split_root({_, _} = root), do: root

  defmacro __using__(_) do
    quote location: :keep do
      @before_compile Elasticlunr.Dsl.Query
      @behaviour Elasticlunr.Dsl.Query
    end
  end

  defmacro __before_compile__(_) do
    mod = __CALLER__.module

    quote bind_quoted: [mod: mod] do
      if not Module.defines?(mod, {:filter, 3}) do
        @impl true
        def filter(query, index, options) do
          query
          |> QueryRepository.score(index, options)
          |> Enum.filter(&(&1.score > 0))
        end
      end

      if not Module.defines?(mod, {:rewrite, 2}) do
        @impl true
        def rewrite(query, _index), do: query
      end
    end
  end
end
