defmodule Elasticlunr.Dsl.MatchAllQuery do
  use Elasticlunr.Dsl.Query

  alias Elasticlunr.Index

  defstruct ~w[boost]a
  @type t :: %__MODULE__{boost: integer()}

  def new(boost \\ 1), do: struct!(__MODULE__, boost: boost)

  @impl true
  def parse(options, _query_options, _repo) do
    options
    |> Map.get("boost", 1)
    |> __MODULE__.new()
  end

  @impl true
  def score(%__MODULE__{boost: boost}, %Index{} = index, _options) do
    doc_ids = Index.all(index)

    Stream.map(doc_ids, &%{ref: &1, score: 1.0 * boost})
  end
end
