defmodule Elasticlunr.Dsl.NotQuery do
  @moduledoc false
  use Elasticlunr.Dsl.Query

  alias Elasticlunr.Index
  alias Elasticlunr.Dsl.{Query, QueryRepository}

  defstruct ~w[inner_query]a
  @type t :: %__MODULE__{inner_query: struct()}

  @spec new(struct()) :: t()
  def new(inner_query), do: %__MODULE__{inner_query: inner_query}

  @impl true
  def parse(options, _query_options, _repo) do
    {key, value} = Query.split_root(options)

    key
    |> QueryRepository.parse(value, options)
    |> new()
  end

  @impl true
  def score(%__MODULE__{inner_query: inner_query}, %Index{} = index, options) do
    query_all = Index.all(index)
    query_score = QueryRepository.score(inner_query, index, options)

    matched_ids = Enum.map(query_score, & &1.ref)

    query_all
    |> Enum.reject(& &1 in matched_ids)
    |> Enum.map(& %{ref: &1, score: 1})
  end
end
