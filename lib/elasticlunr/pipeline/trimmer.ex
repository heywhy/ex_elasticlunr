defmodule Elasticlunr.Pipeline.Trimmer do
  @moduledoc false

  alias Elasticlunr.Token

  @behaviour Elasticlunr.Pipeline

  @impl true
  def call(%Token{token: str} = token, _tokens) do
    str = Regex.replace(~r/^\W+/, str, "")
    str = Regex.replace(~r/\W+$/, str, "")

    Token.update(token, token: str)
  end
end
