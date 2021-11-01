defmodule Elasticlunr.Index do
  @moduledoc false

  alias Elasticlunr.{Field, Pipeline}

  @fields ~w[fields name ref pipeline]a
  @enforce_keys @fields
  defstruct @fields

  @type document_ref :: atom() | binary()
  @type document_field :: atom() | binary()

  @type t :: %__MODULE__{
          fields: map(),
          ref: document_ref(),
          pipeline: Pipeline.t(),
          name: atom() | binary()
        }

  @spec new(atom(), Pipeline.t(), keyword()) :: t()
  def new(name, pipeline, opts \\ []) do
    attrs = %{
      name: name,
      pipeline: pipeline,
      ref: Keyword.get(opts, :ref, :id),
      fields: Keyword.get(opts, :fields, []) |> transform_fields()
    }

    struct!(__MODULE__, attrs)
  end

  @spec add_field(t(), document_field(), keyword()) :: t()
  def add_field(%__MODULE__{fields: fields} = index, field, opts \\ []) do
    %{index | fields: Map.put(fields, field, Field.new(opts))}
  end

  @spec save_document(t(), boolean()) :: t()
  def save_document(%__MODULE__{fields: fields} = index, save) do
    fields =
      fields
      |> Enum.map(fn {key, field} -> {key, %{field | store: save}} end)
      |> Enum.into(%{})

    %{index | fields: fields}
  end

  defp transform_fields(fields) do
    fields
    |> Enum.map(fn
      {field, options} ->
        {field, Field.new(options)}

      field ->
        {field, Field.new([])}
    end)
    |> Enum.into(%{})
  end
end
