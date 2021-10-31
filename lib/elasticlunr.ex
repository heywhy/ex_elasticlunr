defmodule Elasticlunr do
  @moduledoc """
  Documentation for `Elasticlunr`.
  """

  alias Elasticlunr.{Index, IndexManager}

  @spec index(atom() | binary()) :: Index.t()
  def index(name, opts \\ []) do
    with index <- Index.new(name, opts),
         false <- IndexManager.loaded?(name),
         {:ok, index} <- IndexManager.load_index(index) do
      index
    else
      true ->
        IndexManager.get(name)
    end
  end
end
