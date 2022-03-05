defmodule Elasticlunr.Scheduler do
  @moduledoc false

  alias Elasticlunr.Index

  @actions ~w[calculate_idf]a

  @spec push(Index.t(), atom()) :: :ok
  def push(index, action) when action in @actions, do: provider().push(index, action)

  defp provider, do: Application.get_env(:elasticlunr, :scheduler, Elasticlunr.Scheduler.Async)

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Elasticlunr.Scheduler.Behaviour
    end
  end
end
