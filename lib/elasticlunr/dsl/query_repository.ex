defmodule Elasticlunr.Dsl.QueryRepository do
  @moduledoc false

  alias Elasticlunr.Dsl.{BoolQuery, MatchAllQuery, MatchQuery, NotQuery, TermsQuery}

  def get(:not), do: NotQuery
  def get(:bool), do: BoolQuery
  def get(:match), do: MatchQuery
  def get(:terms), do: TermsQuery
  def get(:match_all), do: MatchAllQuery
  def get(element), do: raise("Unknown query type #{element}")

  def parse(module, options, query_options \\ [], repo \\ __MODULE__) do
    module = get(module)
    module.parse(options, query_options, repo)
  end

  def score(query, index, options \\ []) when is_struct(query) do
    query.__struct__.score(query, index, options)
  end

  def filter(query, index, options \\ []) when is_struct(query) do
    query.__struct__.filter(query, index, options)
  end

  def rewrite(query, index) when is_struct(query) do
    query.__struct__.rewrite(query, index)
  end

  def rewrite(query, index, options) when is_struct(query) do
    query.__struct__.filter(query, index, options)
  end
end
