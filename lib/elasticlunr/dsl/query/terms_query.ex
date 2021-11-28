defmodule Elasticlunr.Dsl.TermsQuery do
  use Elasticlunr.Dsl.Query

  alias Elasticlunr.Dsl.Query
  alias Elasticlunr.{Index, Token}

  defstruct ~w[minimum_should_match expand field terms boost fuzziness]a

  @type t :: %__MODULE__{
          minimum_should_match: pos_integer(),
          expand: boolean(),
          field: Index.document_field(),
          terms: list(Token.t()),
          boost: integer(),
          fuzziness: integer()
        }

  @options ~w[boost expand fuzziness minimum_should_match]

  @spec new(keyword()) :: t()
  def new(opts) do
    attrs = %{
      minimum_should_match: Keyword.get(opts, :minimum_should_match, 1),
      expand: Keyword.get(opts, :expand, false),
      field: Keyword.get(opts, :field, ""),
      terms: Keyword.get(opts, :terms, []),
      boost: Keyword.get(opts, :boost, 1),
      fuzziness: Keyword.get(opts, :fuzziness, 0)
    }

    struct!(__MODULE__, attrs)
  end

  @impl true
  def score(
        %__MODULE__{
          boost: boost,
          field: field,
          expand: expand,
          terms: terms,
          fuzziness: fuzziness,
          minimum_should_match: minimum_should_match
        },
        %Index{} = index,
        options \\ []
      ) do
    terms =
      case expand do
        true ->
          Enum.map(terms, fn
            %Token{token: token} ->
              Regex.compile!("^#{token}.*")

            token ->
              Regex.compile!("^#{token}.*")
          end)

        false ->
          terms
      end

    query = [
      field: field,
      terms: terms,
      fuzziness: fuzziness,
      minimum_should_match: minimum_should_match
    ]

    query =
      case Keyword.get(options, :filtered) do
        nil ->
          query

        filtered when is_list(filtered) ->
          Keyword.put(query, :docs, filtered)
      end

    docs = Index.terms(index, query)

    pick_score = fn a, b ->
      if(hd(a) > hd(b), do: a, else: b)
    end

    Stream.map(docs, &elem(&1, 0))
    |> Enum.reduce([], fn id, matched ->
      [score, doc] =
        Map.get(docs, id)
        |> Stream.map(fn doc ->
          [doc.tf * :math.pow(doc.idf, 2) * doc.norm, doc]
        end)
        |> Enum.reduce([0, nil], pick_score)

      ob = %{
        ref: id,
        field: field,
        score: score * boost,
        positions: Map.put(%{}, field, doc.positions)
      }

      matched ++ [ob]
    end)
  end

  @impl true
  def parse(options, _query_options, repo) do
    cond do
      Enum.empty?(options) ->
        repo.parse("match_all", %{})

      Enum.count(options) > 1 ->
        should =
          options
          |> Enum.reject(fn {key, _field} -> key in @options end)
          |> Enum.map(fn {field, terms} ->
            %{"terms" => %{field => terms}}
          end)

        repo.parse("bool", %{"should" => should})

      true ->
        {field, params} = Query.split_root(options)
        terms = get_terms(params)
        opts = to_terms_params(params)

        __MODULE__.new([field: field, terms: terms] ++ opts)
    end
  end

  defp get_terms(params) when is_map(params) do
    params
    |> Map.get("query")
    |> to_list()
  end

  defp get_terms(value), do: to_list(value)

  defp to_terms_params(params) when is_map(params) do
    []
    |> update_options(params, :minimum_should_match)
    |> update_options(params, :fuzziness)
    |> update_options(params, :expand)
    |> update_options(params, :boost)
  end

  defp to_terms_params(params), do: to_terms_params(%{"query" => params})

  defp update_options(opts, params, key) do
    case Map.get(params, to_string(key)) do
      nil ->
        opts

      value ->
        Keyword.put(opts, key, value)
    end
  end

  defp to_list(value) when is_list(value), do: value
  defp to_list(value), do: [value]
end
