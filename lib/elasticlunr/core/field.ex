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

  @spec add(t(), list(%{id: Index.document_ref(), content: binary()})) :: t()
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
end
