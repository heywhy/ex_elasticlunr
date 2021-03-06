defmodule Elasticlunr.Pipeline.Trimmer do
  alias Elasticlunr.Token

  @behaviour Elasticlunr.Pipeline

  @impl true
  def call(%Token{token: str} = token) do
    str = Regex.replace(~r/^\W+/, str, "")
    str = Regex.replace(~r/\W+$/, str, "")

    Token.update(token, token: str)
  end
end
