defmodule Elasticlunr.Dsl.QueryRepository do
  alias Elasticlunr.Core.Index
  alias Elasticlunr.Dsl.{BoolQuery, MatchAllQuery, MatchQuery, NotQuery, TermsQuery}

  def get("not"), do: NotQuery
  def get("bool"), do: BoolQuery
  def get("match"), do: MatchQuery
  def get("terms"), do: TermsQuery
  def get("match_all"), do: MatchAllQuery
  def get(element), do: raise("Unknown query type #{element}")

  @spec parse(binary(), map(), map(), module()) :: struct()
  def parse(module, options, query_options \\ %{}, repo \\ __MODULE__) do
    module = get(module)
    module.parse(options, query_options, repo)
  end

  @spec score(struct(), Index.t(), keyword()) :: list()
  def score(query, index, options \\ []) when is_struct(query) do
    query.__struct__.score(query, index, options)
  end

  @spec filter(struct(), Index.t(), keyword()) :: list()
  def filter(query, index, options \\ []) when is_struct(query) do
    query.__struct__.filter(query, index, options)
  end

  @spec rewrite(struct(), Index.t()) :: struct()
  def rewrite(query, index) when is_struct(query) do
    query.__struct__.rewrite(query, index)
  end
end
