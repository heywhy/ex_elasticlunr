defmodule Elasticlunr.Dsl.MatchAllQuery do
  @moduledoc false
  use Elasticlunr.Dsl.Query

  alias Elasticlunr.Index

  defstruct ~w[boost]a
  @type t :: %__MODULE__{boost: integer()}

  def new(boost \\ 1), do: struct!(__MODULE__, boost: boost)

  @impl true
  def parse(options, _query_options, _repo) do
    options
    |> Keyword.get(:boost, 1)
    |> __MODULE__.new()
  end
end
