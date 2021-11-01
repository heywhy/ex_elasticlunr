defmodule Elasticlunr.Dsl.TermsQuery do
  @moduledoc false
  use Elasticlunr.Dsl.Query

  defstruct ~w[inner_query]a
  @type t :: %__MODULE__{inner_query: struct()}

  @spec new(keyword()) :: t()
  def new(opts) do
    attrs = %{}

    struct!(__MODULE__, attrs)
  end
end
