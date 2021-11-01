defmodule Elasticlunr.Field do
  @moduledoc false

  alias Elasticlunr.{Index, Pipeline}

  @fields ~w[pipeline query_pipeline store store_positions flnorm tf idf ids documents terms]a

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          pipeline: Pipeline.t() | nil,
          query_pipeline: Pipeline.t() | nil,
          store: boolean(),
          store_positions: boolean(),
          flnorm: integer(),
          tf: map(),
          idf: map(),
          terms: map(),
          documents: map(),
          ids: list(Index.document_ref())
        }

  @type document :: %{id: Index.document_ref(), content: binary()}

  @spec new(keyword) :: t()
  def new(opts) do
    attrs = %{
      ids: [],
      tf: %{},
      idf: %{},
      flnorm: 1,
      terms: %{},
      documents: %{},
      pipeline: Keyword.get(opts, :pipeline),
      query_pipeline: Keyword.get(opts, :query_pipeline),
      store: Keyword.get(opts, :save_documents, true),
      store_positions: Keyword.get(opts, :store_positions, true)
    }

    struct!(__MODULE__, attrs)
  end

  @spec add(t(), list(document())) :: t()
  def add(%__MODULE__{ids: ids, store: store, pipeline: _pipeline} = field, documents) do
    Enum.reduce(documents, field, fn %{id: id, content: content}, field ->
      if content in ids do
        raise "Document id #{id} already exists in the index"
      end

      field =
        case store do
          false ->
            field

          true ->
            %{documents: documents} = field
            %{field | documents: Map.put(documents, id, content)}
        end

      %{ids: ids} = field
      field = %{field | ids: [id] ++ ids}

      # pipeline.run(content)

      field
    end)
  end

  @spec update(t(), list(document())) :: t()
  def update(%__MODULE__{} = field, documents) do
    document_ids = Enum.map(documents, & &1.id)

    field
    |> remove(document_ids)
    |> add(documents)
  end

  @spec remove(t(), list(Index.document_ref())) :: t()
  def remove(%__MODULE__{} = field, document_ids) do
    document_ids
    |> Enum.reduce(field, fn document_id, %{ids: ids, documents: documents} = field ->
      documents = Map.delete(documents, document_id)
      ids = Enum.reject(ids, &(&1 == document_id))

      %{field | ids: ids, documents: documents}
    end)
  end

  @spec analyze(t(), any(), keyword) :: list(Token.t())
  def analyze(%__MODULE__{pipeline: pipeline, query_pipeline: query_pipeline}, str, options) do
    case Keyword.get(options, :is_query, false) && not is_nil(query_pipeline) do
      true ->
        Pipeline.run(query_pipeline, str)

      false ->
        Pipeline.run(pipeline, str)
    end
  end
end
