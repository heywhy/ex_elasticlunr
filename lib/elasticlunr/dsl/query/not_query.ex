defmodule Elasticlunr.Dsl.NotQuery do
  @moduledoc false
  use Elasticlunr.Dsl.Query

  alias Elasticlunr.Index

  defstruct ~w[index]a
  @type t :: %__MODULE__{index: Index.t()}

  def new() do
  end
end
