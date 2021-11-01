defmodule Elasticlunr do
  @moduledoc """
  Documentation for `Elasticlunr`.
  """

  alias Elasticlunr.{Index, IndexManager, Pipeline}

  @spec index(atom() | binary()) :: Index.t() | :not_running
  def index(name, opts \\ []) do
    with pipeline <- with_default_pipeline(opts),
         index <- Index.new(name, pipeline, opts),
         false <- IndexManager.loaded?(name),
         {:ok, index} <- IndexManager.load_index(index) do
      index
    else
      true ->
        IndexManager.get(name)
    end
  end

  @spec update_index(Index.t()) :: Index.t() | :not_running
  def update_index(%Index{} = index) do
    IndexManager.update_index(index)
  end

  @spec default_pipeline() :: Pipeline.t()
  def default_pipeline, do: Pipeline.new(Pipeline.default_runners())

  defp with_default_pipeline(_opts), do: default_pipeline()
end
