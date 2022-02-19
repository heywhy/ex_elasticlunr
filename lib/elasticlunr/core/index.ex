defmodule Elasticlunr.Index.IdPipeline do
  @moduledoc false

  alias Elasticlunr.{Pipeline, Token}

  @behaviour Pipeline

  @impl true
  def call(%Token{} = token), do: token
end

defmodule Elasticlunr.Index do
  alias Elasticlunr.{Field, Operation, Pipeline}
  alias Elasticlunr.Index.IdPipeline

  defstruct ~w[fields name ref pipeline documents_size store_positions store_documents ops]a

  @type t :: %__MODULE__{
          fields: map(),
          documents_size: integer(),
          ref: Field.document_ref(),
          pipeline: Pipeline.t(),
          name: atom() | binary(),
          store_positions: boolean(),
          store_documents: boolean(),
          ops: list(Operation.t())
        }

  @type document_field :: atom() | binary()

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    ref = Keyword.get(opts, :ref, "id")
    pipeline = Keyword.get_lazy(opts, :pipeline, &Pipeline.new/0)

    fields = Map.put(%{}, ref, Field.new(pipeline: Pipeline.new([IdPipeline])))

    attrs = [
      documents_size: 0,
      ref: ref,
      fields: fields,
      pipeline: pipeline,
      name: Keyword.get_lazy(opts, :name, &UUID.uuid4/0),
      store_documents: Keyword.get(opts, :store_documents, true),
      store_positions: Keyword.get(opts, :store_positions, true)
    ]

    ops = [Operation.new(:initialize, attrs)]

    struct!(__MODULE__, [ops: ops] ++ attrs)
  end

  @spec add_field(t(), document_field(), keyword()) :: t()
  def add_field(
        %__MODULE__{
          fields: fields,
          pipeline: pipeline,
          store_positions: store_positions,
          store_documents: store_documents
        } = index,
        field,
        opts \\ []
      )
      when is_binary(field) do
    opts =
      opts
      |> Keyword.put_new(:name, field)
      |> Keyword.put_new(:type, :text)
      |> Keyword.put_new(:pipeline, pipeline)
      |> Keyword.put_new(:store_documents, store_documents)
      |> Keyword.put_new(:store_positions, store_positions)

    fields = Map.put(fields, field, Field.new(opts))

    index
    |> Map.put(:fields, fields)
    |> with_operation(Operation.new(:add_field, opts))
  end

  @spec get_fields(t()) :: list(Field.document_ref() | document_field())
  def get_fields(%__MODULE__{fields: fields}), do: Map.keys(fields)

  @spec get_field(t(), document_field()) :: Field.t()
  def get_field(%__MODULE__{fields: fields}, field) do
    Map.get(fields, field)
  end

  @spec save_document(t(), boolean()) :: t()
  def save_document(%__MODULE__{fields: fields} = index, save) do
    fields =
      fields
      |> Enum.map(fn {key, field} -> {key, %{field | store: save}} end)
      |> Enum.into(%{})

    op = Operation.new(:save_document, save)

    with_operation(%{index | fields: fields}, op)
  end

  @spec add_documents(t(), list(map())) :: t()
  def add_documents(%__MODULE__{} = index, documents) do
    op = Operation.new(:add_documents, documents)

    with_operation(index, op)
  end

  defp with_operation(%{ops: ops} = index, op) do
    %{index | ops: ops ++ [op]}
  end
end
