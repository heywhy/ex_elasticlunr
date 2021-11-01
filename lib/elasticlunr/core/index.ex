defmodule Elasticlunr.Index do
  @moduledoc false

  alias Elasticlunr.{Field, Pipeline}

  @fields ~w[fields name ref pipeline documents_size]a
  @enforce_keys @fields
  defstruct @fields

  @type document_ref :: atom() | binary()
  @type document_field :: atom() | binary()

  @type t :: %__MODULE__{
          fields: map(),
          documents_size: integer(),
          ref: document_ref(),
          pipeline: Pipeline.t(),
          name: atom() | binary()
        }

  @spec new(atom(), Pipeline.t(), keyword()) :: t()
  def new(name, pipeline, opts \\ []) do
    attrs = %{
      name: name,
      documents_size: 0,
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

  @spec get_fields(t()) :: list(document_ref() | document_field())
  def get_fields(%__MODULE__{fields: fields}), do: Map.keys(fields)

  @spec save_document(t(), boolean()) :: t()
  def save_document(%__MODULE__{fields: fields} = index, save) do
    fields =
      fields
      |> Enum.map(fn {key, field} -> {key, %{field | store: save}} end)
      |> Enum.into(%{})

    %{index | fields: fields}
  end

  @spec add_documents(t(), list(map())) :: t()
  def add_documents(%__MODULE__{ref: ref, fields: fields} = index, documents) do
    transform_document = fn {key, content}, {document, fields} ->
      case Map.get(fields, key) do
        nil ->
          {document, fields}

        %Field{} = field ->
          id = Map.get(document, ref)
          field = Field.add(field, [%{id: id, content: content}])
          fields = Map.put(fields, key, field)

          {document, fields}
      end
    end

    fields =
      Enum.reduce(documents, fields, fn document, fields ->
        document
        |> Enum.reduce({document, fields}, transform_document)
        |> elem(1)
      end)

    update_documents_size(%{index | fields: fields})
  end

  @spec remove_documents(t(), list(document_ref())) :: t()
  def remove_documents(%__MODULE__{fields: fields} = index, document_ids) do
    fields =
      Enum.reduce(fields, fields, fn {key, field}, fields ->
        field = Field.remove(field, document_ids)

        fields
        |> Map.put(key, field)
      end)

    update_documents_size(%{index | fields: fields})
  end

  defp update_documents_size(%__MODULE__{fields: fields} = index) do
    size =
      index
      |> get_fields()
      |> Enum.map(&Map.get(fields, &1))
      |> Enum.map(&Enum.count(&1.ids))
      |> Enum.reduce(0, fn size, acc ->
        case size > acc do
          true ->
            size

          false ->
            acc
        end
      end)

    %{index | documents_size: size}
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
