defmodule Elasticlunr.Token do
  @moduledoc false

  defstruct ~w[token metadata]a

  @type t :: %__MODULE__{
          token: binary(),
          metadata: map()
        }

  @spec new(binary(), map()) :: t()
  def new(token, metadata \\ %{}) do
    struct!(__MODULE__, token: token, metadata: metadata)
  end

  @spec update(t(), keyword()) :: t()
  def update(%__MODULE__{token: str, metadata: metadata} = token, opts) do
    opts =
      opts
      |> Keyword.put_new(:token, str)
      |> Keyword.put_new(:metadata, metadata)

    struct!(token, opts)
  end

  @spec get_position(t()) :: {integer(), integer()} | nil
  def get_position(%__MODULE__{metadata: %{start: start, end: end_1}}), do: {start, end_1}
  def get_position(%__MODULE__{metadata: %{}}), do: nil
end
