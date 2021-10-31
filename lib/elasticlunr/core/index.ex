defmodule Elasticlunr.Index do
  @moduledoc false

  alias Elasticlunr.Pipeline

  @fields ~w[fields name ref pipeline]a
  @enforce_keys @fields
  defstruct @fields

  @type document_ref :: atom() | binary()
  @type document_field :: atom() | binary()

  @type t :: %__MODULE__{
          ref: document_ref(),
          fields: list(atom()),
          pipeline: Pipeline.t(),
          name: atom() | binary()
        }

  @spec new(atom(), Pipeline.t(), keyword()) :: t()
  def new(name, pipeline, opts \\ []) do
    attrs = %{
      name: name,
      pipeline: pipeline,
      ref: Keyword.get(opts, :ref, :id),
      fields: Keyword.get(opts, :fields, [])
    }

    struct!(__MODULE__, attrs)
  end
end
