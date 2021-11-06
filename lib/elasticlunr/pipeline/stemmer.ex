defmodule Elasticlunr.Pipeline.Stemmer do
  alias Elasticlunr.Token

  @behaviour Elasticlunr.Pipeline

  @impl true
  def call(%Token{token: str} = token) do
    Token.update(token, token: Stemmer.stem(str))
  end
end
