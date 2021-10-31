defmodule Elasticlunr.Token do
  @moduledoc false

  defstruct ~w[token metadata]a

  @type t :: %__MODULE__{
          token: binary(),
          metadata: map()
        }

  def new(token, metadata) do
    struct!(__MODULE__, token: token, metadata: metadata)
  end
end
