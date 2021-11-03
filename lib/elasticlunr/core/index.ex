defmodule Elasticlunr.Index.IdPipeline do
  @moduledoc false

  alias Elasticlunr.{Pipeline, Token}

  @behaviour Pipeline

  @impl true
  def call(%Token{token: str}) do
    [str]
  end
end

defmodule Elasticlunr.Index do
  @moduledoc false

  alias Elasticlunr.{Field, Pipeline, Token}
  alias Elasticlunr.Index.IdPipeline
  alias Elasticlunr.Dsl.{Query, QueryRepository}

  @fields ~w[fields name ref pipeline documents_size store_positions store_documents]a
  @enforce_keys @fields
  defstruct @fields

  @type document_ref :: atom() | binary()
  @type document_field :: atom() | binary()

  @type t :: %__MODULE__{
          fields: map(),
          documents_size: integer(),
          ref: document_ref(),
          pipeline: Pipeline.t(),
          name: atom() | binary(),
          store_positions: boolean(),
          store_documents: boolean()
        }

  @type search_query :: binary() | keyword()
  @type search_result :: any()

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    ref = Keyword.get(opts, :ref, :id)
    pipeline = Keyword.get(opts, :pipeline, Pipeline.new())

    attrs = %{
      documents_size: 0,
      ref: ref,
      pipeline: pipeline,
      fields: %{},
      name: Keyword.get_lazy(opts, :name, &UUID.uuid4/0),
      store_documents: Keyword.get(opts, :store_documents, true),
      store_positions: Keyword.get(opts, :store_positions, true)
    }

    ob = struct!(__MODULE__, attrs)

    field =
      opts
      |> Keyword.get(:fields, [])
      |> Keyword.delete(ref)
      |> Enum.reduce(ob, fn
        field, ob -> add_field(ob, field)
      end)

    fields =
      field
      |> Map.get(:fields)
      |> Map.put(ref, Field.new(pipeline: Pipeline.new([IdPipeline])))

    %{field | fields: fields}
  end

  @spec add_field(t(), document_field(), keyword()) :: t()
  def add_field(
        %__MODULE__{
          fields: fields,
          pipeline: pipeline,
          store_documents: store_documents
        } = index,
        field,
        opts \\ []
      ) do
    opts =
      opts
      |> Keyword.put_new(:pipeline, pipeline)
      |> Keyword.put_new(:store_documents, store_documents)
      |> Keyword.put(:store_positions, true)

    %{index | fields: Map.put(fields, field, Field.new(opts))}
  end

  @spec get_fields(t()) :: list(document_ref() | document_field())
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

  @spec update_documents(t(), list(map())) :: t()
  def update_documents(%__MODULE__{ref: ref, fields: fields} = index, documents) do
    transform_document = fn {key, content}, {document, fields} ->
      case Map.get(fields, key) do
        nil ->
          {document, fields}

        %Field{} = field ->
          id = Map.get(document, ref)
          field = Field.update(field, [%{id: id, content: content}])
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

  @spec analyze(t(), document_field(), any(), keyword()) :: Token.t() | list(Token.t())
  def analyze(%__MODULE__{fields: fields}, field, content, options) do
    fields
    |> Map.get(field)
    |> Field.analyze(content, options)
  end

  @spec terms(t(), keyword()) :: any()
  def terms(%__MODULE__{fields: fields}, query) do
    field = Keyword.get(query, :field)

    fields
    |> Map.get(field)
    |> Field.terms(query)
  end

  @spec all(t()) :: list(document_ref())
  def all(%__MODULE__{ref: ref, fields: fields}) do
    fields
    |> Map.get(ref)
    |> Field.all()
  end

  @spec search(t(), search_query(), keyword()) :: list(search_result())
  def search(index, query, opts \\ nil)
  def search(%__MODULE__{}, nil, _opts), do: []

  def search(%__MODULE__{ref: ref} = index, query, nil) when is_binary(query) do
    fields = get_fields(index)

    matches =
      fields
      |> Enum.reject(&(&1 == ref))
      |> Enum.map(fn field ->
        match = Keyword.put([], field, query)
        [match: match]
      end)

    elasticsearch(index,
      query: [
        bool: [
          should: matches
        ]
      ]
    )
  end

  def search(%__MODULE__{ref: ref} = index, query, fields: fields) when is_binary(query) do
    matches =
      fields
      |> Enum.filter(fn field ->
        with true <- field != ref,
             true <- Keyword.has_key?(fields, field),
             [boost: boost] <- Keyword.get(fields, field) do
          boost > 0
        end
      end)
      |> Enum.map(fn field ->
        [boost: boost] = Keyword.get(fields, field)
        match = Keyword.put([], field, query)

        [match: match, boost: boost]
      end)

    elasticsearch(index,
      query: [
        bool: [
          should: matches
        ]
      ]
    )
  end

  def search(%__MODULE__{} = index, [query: _] = query, _opts), do: elasticsearch(index, query)

  def search(%__MODULE__{} = index, query, nil) when is_list(query),
    do: search(index, query, operator: "OR")

  def search(%__MODULE__{} = index, [] = query, options) do
    matches =
      query
      |> Enum.map(fn {field, content} ->
        expand = Keyword.get(options, :expand, false)

        operator =
          options
          |> Keyword.get(:bool, "or")
          |> String.downcase()

        [
          expand: expand,
          match: Keyword.put([operator: operator], field, content)
        ]
      end)

    elasticsearch(index,
      query: [
        bool: [
          should: matches
        ]
      ]
    )
  end

  defp elasticsearch(index, query: root) do
    {key, value} = Query.split_root(root)

    query = QueryRepository.parse(key, value, root)

    query
    |> QueryRepository.score(index)
    |> Enum.sort(fn a, b -> a.score < b.score end)
  end

  defp elasticsearch(_index, _query) do
    raise "Root object must have a query element"
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

  defp transform_fields(fields, opts) do
    fields
    |> Enum.map(fn
      {field, options} ->
        {field, Field.new(options ++ opts)}

      field ->
        {field, Field.new(opts)}
    end)
    |> Enum.into(%{})
  end
end
