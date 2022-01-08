defmodule Elasticlunr.Dsl.MatchQuery do
  use Elasticlunr.Dsl.Query

  alias Elasticlunr.{Index}
  alias Elasticlunr.Dsl.{MatchAllQuery, Query, QueryRepository, TermsQuery}

  defstruct ~w[expand field query boost fuzziness minimum_should_match operator]a

  @type t :: %__MODULE__{
          expand: boolean(),
          boost: integer(),
          field: Index.document_field(),
          query: any(),
          fuzziness: integer(),
          operator: binary(),
          minimum_should_match: pos_integer()
        }

  @spec new(keyword) :: t()
  def new(opts) do
    attrs = %{
      expand: Keyword.get(opts, :expand, false),
      field: Keyword.get(opts, :field, ""),
      query: Keyword.get(opts, :query, ""),
      boost: Keyword.get(opts, :boost, 1),
      fuzziness: Keyword.get(opts, :fuzziness, 0),
      operator: Keyword.get(opts, :operator, "or"),
      minimum_should_match: Keyword.get(opts, :minimum_should_match, 1)
    }

    struct!(__MODULE__, attrs)
  end

  @impl true
  def rewrite(
        %__MODULE__{
          boost: boost,
          field: field,
          query: query,
          expand: expand,
          operator: operator,
          fuzziness: fuzziness,
          minimum_should_match: minimum_should_match
        },
        %Index{} = index
      ) do
    tokens =
      index
      |> Index.analyze(field, query, is_query: true)
      |> case do
        tokens when is_list(tokens) ->
          tokens

        token ->
          [token]
      end

    tokens_length = length(tokens)

    cond do
      tokens_length > 1 ->
        minimum_should_match =
          case operator == "and" && minimum_should_match == 0 do
            true ->
              tokens_length

            false ->
              minimum_should_match
          end

        TermsQuery.new(
          field: field,
          expand: expand,
          terms: tokens,
          fuzziness: fuzziness,
          boost: boost,
          minimum_should_match: minimum_should_match
        )

      tokens_length == 1 ->
        [token] = tokens

        TermsQuery.new(
          field: field,
          expand: expand,
          terms: [token],
          fuzziness: fuzziness,
          boost: boost
        )

      true ->
        MatchAllQuery.new()
    end
  end

  @impl true
  def score(%__MODULE__{} = module, %Index{} = index, options) do
    module
    |> rewrite(index)
    |> QueryRepository.score(index, options)
  end

  @impl true
  def parse(options, _query_options, repo) do
    cond do
      Enum.empty?(options) ->
        repo.parse("match_all", %{})

      Enum.count(options) > 1 ->
        minimum_should_match = Enum.count(options)

        should =
          Enum.map(options, fn {field, content} ->
            %{"match" => %{field => content}}
          end)

        repo.parse("bool", %{
          "should" => should,
          "minimum_should_match" => minimum_should_match
        })

      true ->
        {field, params} = Query.split_root(options)

        opts = to_match_params(params)

        __MODULE__.new(
          field: field,
          query: Keyword.get(opts, :query),
          expand: Keyword.get(opts, :expand),
          operator: Keyword.get(opts, :operator),
          fuzziness: Keyword.get(opts, :fuzziness),
          minimum_should_match: Keyword.get(opts, :minimum_should_match)
        )
    end
  end

  defp to_match_params(params) when is_map(params) do
    query = Map.get(params, "query")
    fuzziness = Map.get(params, "fuzziness", 0)
    operator = Map.get(params, "operator", "or")
    expand = Map.get(params, "expand", false)

    minimum_should_match = Map.get(params, "minimum_should_match", default_min_match(params))

    [
      query: query,
      expand: expand,
      operator: operator,
      fuzziness: fuzziness,
      minimum_should_match: minimum_should_match
    ]
  end

  defp to_match_params(params), do: to_match_params(%{"query" => params})

  defp default_min_match(params) do
    case Map.get(params, "operator") == "and" do
      true ->
        0

      false ->
        1
    end
  end
end
