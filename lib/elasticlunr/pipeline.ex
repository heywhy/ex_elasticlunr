defmodule Elasticlunr.Pipeline do
  @moduledoc false

  alias Elasticlunr.Token

  defstruct callback: []
  @type t :: %__MODULE__{
    callback: list()
  }

  @callback call(Token.t()) :: Token.t()

  def new(callbacks) when is_list(callbacks) do
    struct!(__MODULE__, %{callback: callbacks})
  end
end
