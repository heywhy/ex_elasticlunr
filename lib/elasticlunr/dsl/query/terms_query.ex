defmodule Elasticlunr.Dsl.TermsQuery do
  @moduledoc false
  use Elasticlunr.Dsl.Query

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
      if expand do
        Enum.map(terms, fn %Token{token: token} ->
          Regex.compile!("^#{token}.*")
        end)
      else
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

        fielded ->
          Keyword.put(query, :docs, fielded)
      end

    docs = Index.terms(index, query)
    ids = Map.keys(docs)

    pick_score = fn a, b ->
      if(hd(b) > hd(a), do: b, else: a)
    end

    Enum.reduce(ids, [], fn id, matched ->
      # [score, doc] = pick_score.(id)
      [score, doc] =
        Map.get(docs, id)
        |> Enum.map(fn doc ->
          [doc.tf * :math.pow(doc.idf, 2) * doc.norm, doc]
        end)
        |> Enum.reduce([0, nil], pick_score)

      ob = %{
        ref: id,
        field: field,
        score: score * boost,
        positions: Map.put(%{}, field, doc.positions)
      }

      [ob] ++ matched
    end)
  end
end
