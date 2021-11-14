defmodule Elasticlunr do
  @moduledoc """
  Documentation for `Elasticlunr`.
  """

  @type index_name :: atom() | binary()

  alias Elasticlunr.{Index, IndexManager, Pipeline}

  @spec index(index_name(), keyword()) :: Index.t() | :not_running
  def index(name, opts \\ []) do
    with opts <- with_default_pipeline([name: name] ++ opts),
         index <- Index.new(opts),
         false <- IndexManager.loaded?(name),
         {:ok, index} <- IndexManager.load_index(index) do
      index
    else
      true ->
        IndexManager.get(name)
    end
  end

  @spec update_index(index_name(), function()) :: Index.t() | :not_running
  def update_index(name, callback) do
    with %Index{} = index <- IndexManager.get(name),
         index <- callback.(index),
         %Index{} = index <- IndexManager.update_index(index) do
      index
    end
  end

  @spec default_pipeline() :: Pipeline.t()
  def default_pipeline, do: Pipeline.new(Pipeline.default_runners())

  defp with_default_pipeline(opts), do: Keyword.put_new(opts, :pipeline, default_pipeline())
end
