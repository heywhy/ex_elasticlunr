defmodule Elasticlunr.Operation do
  @moduledoc false

  defstruct ~w[type params]a

  @mutations ~w[add_documents update_document]a
  @types ~w[initialize add_field update_field save_document]a ++ @mutations

  @type t :: %__MODULE__{
          type: atom(),
          params: any()
        }

  @spec new(atom(), any()) :: t()
  def new(type, params) when type in @types do
    struct!(__MODULE__, type: type, params: params)
  end

  @spec mutates_result?(t()) :: boolean()
  def mutates_result?(%__MODULE__{type: type}), do: type in @mutations
end
