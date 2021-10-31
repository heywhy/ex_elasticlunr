defmodule Elasticlunr.Pipeline.Stemmer do
  @moduledoc false

  @behaviour Elasticlunr.Pipeline

  @impl true
  def call(token) do
    token
  end
end
