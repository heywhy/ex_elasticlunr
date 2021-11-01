defmodule Elasticlunr.Dsl.QueryRepository do
  @moduledoc false

  alias Elasticlunr.Dsl.{BoolQuery, MatchAllQuery, MatchQuery, NotQuery}

  def get(:not), do: NotQuery
  def get(:bool), do: BoolQuery
  def get(:match), do: MatchQuery
  def get(:match_all), do: MatchAllQuery
  def get(element), do: raise("Unknown query type #{element}")

  def parse(module, options, query_options \\ %{}, repo \\ __MODULE__) do
    module = get(module)
    module.parse(options, query_options, repo)
  end

  def score(query, index) when is_struct(query) do
    # credo:disable-for-next-line
    IO.inspect(query)

    query.__struct__.score(query, index)
  end
end
