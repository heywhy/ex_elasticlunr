defmodule Elasticlunr.Pipeline.Stemmer do
  @moduledoc false

  @behaviour Elasticlunr.Pipeline

  @impl true
  def call(token, _tokens) do
    token
  end
end
