defmodule Elasticlunr.Dsl.NotQuery do
  @moduledoc false
  use Elasticlunr.Dsl.Query

  defstruct ~w[inner_query]a
  @type t :: %__MODULE__{inner_query: struct()}

  @spec new(struct()) :: t()
  def new(inner_query), do: %__MODULE__{inner_query: inner_query}
end
