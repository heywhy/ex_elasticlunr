defmodule Elasticlunr.Index do
  @moduledoc false

  @enforce_keys ~w[fields name ref]a
  defstruct name: nil, ref: :id, fields: []

  @type document_ref :: atom() | binary()
  @type document_field :: atom() | binary()

  @type t :: %__MODULE__{
          ref: document_ref(),
          fields: list(atom()),
          name: atom() | binary()
        }

  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) do
    attrs = %{
      name: name,
      ref: Keyword.get(opts, :ref, :id),
      fields: Keyword.get(opts, :fields, [])
    }

    struct!(__MODULE__, attrs)
  end
end
