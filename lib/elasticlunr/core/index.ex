defmodule Elasticlunr.Index.IdPipeline do
  @moduledoc false

  alias Elasticlunr.{Pipeline, Token}

  @behaviour Pipeline

  @impl true
  def call(%Token{} = token), do: token
end

defmodule Elasticlunr.Index do
  alias Elasticlunr.{DB, Field, Pipeline, Scheduler}
  alias Elasticlunr.Index.IdPipeline
  alias Elasticlunr.Dsl.{Query, QueryRepository}

  @fields ~w[db fields name ref pipeline documents_size store_positions store_documents on_conflict]a
  @enforce_keys @fields
  defstruct @fields

  @type document_field :: atom() | binary()

  @type t :: %__MODULE__{
          db: DB.t(),
          fields: map(),
          documents_size: integer(),
          ref: Field.document_ref(),
          pipeline: Pipeline.t(),
          name: atom() | binary(),
          store_positions: boolean(),
          store_documents: boolean()
        }

  @type search_query :: binary() | map()
  @type search_result :: any()

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    ref = Keyword.get(opts, :ref, "id")
    pipeline = Keyword.get_lazy(opts, :pipeline, &Pipeline.new/0)

    name = Keyword.get_lazy(opts, :name, &UUID.uuid4/0)
    db_name = String.to_atom("elasticlunr_#{name}")
    db = DB.init(db_name, ~w[ordered_set public]a)

    id_field = Field.new(db: db, name: ref, pipeline: Pipeline.new([IdPipeline]))
    fields = Map.put(%{}, to_string(ref), id_field)

    attrs = %{
      db: db,
      documents_size: 0,
      ref: ref,
      fields: fields,
      pipeline: pipeline,
      name: name,
      on_conflict: Keyword.get(opts, :on_conflict, :index),
      store_documents: Keyword.get(opts, :store_documents, true),
      store_positions: Keyword.get(opts, :store_positions, true)
    }

    struct!(__MODULE__, attrs)
  end

  @spec add_field(t(), document_field(), keyword()) :: t()
  def add_field(
        %__MODULE__{
          db: db,
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
      |> Keyword.put(:db, db)
      |> Keyword.put(:name, field)
      |> Keyword.put_new(:pipeline, pipeline)
      |> Keyword.put_new(:store_documents, store_documents)
      |> Keyword.put_new(:store_positions, store_positions)

    %{index | fields: Map.put(fields, field, Field.new(opts))}
  end

  @spec update_field(t(), document_field(), Field.t()) :: t()
  def update_field(%__MODULE__{fields: fields} = index, name, %Field{} = field) do
    if not Map.has_key?(fields, name) do
      raise "Unknown field #{name} in index"
    end

    update_documents_size(%{index | fields: Map.put(fields, name, field)})
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

    %{index | fields: fields}
  end

  @spec add_documents(t(), list(map()), keyword()) :: t()
  def add_documents(
        %__MODULE__{fields: fields, on_conflict: on_conflict, ref: ref} = index,
        documents,
        opts \\ []
      ) do
    opts = Keyword.put_new(opts, :on_conflict, on_conflict)
    :ok = persist(fields, ref, documents, &Field.add(&1, &2, opts))
    :ok = Scheduler.push(index, :calculate_idf)

    update_documents_size(index)
  end

  @spec update_documents(t(), list(map())) :: t()
  def update_documents(%__MODULE__{ref: ref, fields: fields} = index, documents) do
    :ok = persist(fields, ref, documents, &Field.update/2)
    :ok = Scheduler.push(index, :calculate_idf)

    update_documents_size(index)
  end

  @spec remove_documents(t(), list(Field.document_ref())) :: t()
  def remove_documents(%__MODULE__{fields: fields} = index, document_ids) do
    Enum.each(fields, fn {_, field} ->
      Field.remove(field, document_ids)
    end)

    :ok = Scheduler.push(index, :calculate_idf)

    update_documents_size(index)
  end

  @spec analyze(t(), document_field(), any(), keyword()) :: Enumerable.t()
  def analyze(%__MODULE__{fields: fields}, field, content, options) do
    fields
    |> Map.get(field)
    |> Field.analyze(content, options)
  end

  @spec terms(t(), keyword()) :: Enumerable.t()
  def terms(%__MODULE__{fields: fields}, query) do
    field = Keyword.get(query, :field)

    fields
    |> Map.get(field)
    |> Field.terms(query)
  end

  @spec all(t()) :: list(Field.document_ref())
  def all(%__MODULE__{ref: ref, fields: fields}) do
    fields
    |> Map.get(ref)
    |> Field.documents()
  end

  @spec update_documents_size(t()) :: t()
  def update_documents_size(%__MODULE__{fields: fields} = index) do
    size =
      Enum.reduce(fields, 0, fn {_, field}, acc ->
        size = Field.length(field, :ids)

        if size > acc do
          size
        else
          acc
        end
      end)

    %{index | documents_size: size}
  end

  @spec search(t(), search_query(), map() | nil) :: list(search_result())
  def search(index, query, opts \\ nil)
  def search(%__MODULE__{}, nil, _opts), do: []

  def search(%__MODULE__{ref: ref} = index, query, nil) when is_binary(query) do
    fields = get_fields(index)

    matches =
      fields
      |> Enum.reject(&(&1 == ref))
      |> Enum.map(fn field ->
        %{"match" => %{field => query}}
      end)

    elasticsearch(index, %{
      "query" => %{
        "bool" => %{
          "should" => matches
        }
      }
    })
  end

  def search(%__MODULE__{ref: ref} = index, query, %{"fields" => fields}) when is_binary(query) do
    matches =
      fields
      |> Enum.filter(fn field ->
        with true <- field != ref,
             true <- Map.has_key?(fields, field),
             %{"boost" => boost} <- Map.get(fields, field) do
          boost > 0
        end
      end)
      |> Enum.map(fn field ->
        %{"boost" => boost} = Map.get(fields, field)
        match = %{field => query}

        %{"match" => match, "boost" => boost}
      end)

    elasticsearch(index, %{
      "query" => %{
        "bool" => %{
          "should" => matches
        }
      }
    })
  end

  def search(%__MODULE__{} = index, %{"query" => _} = query, _opts),
    do: elasticsearch(index, query)

  def search(%__MODULE__{} = index, query, nil) when is_map(query),
    do: search(index, query, %{"operator" => "OR"})

  def search(%__MODULE__{} = index, %{} = query, options) do
    matches =
      query
      |> Enum.map(fn {field, content} ->
        expand = Map.get(options, "expand", false)

        operator =
          options
          |> Map.get("bool", "or")
          |> String.downcase()

        %{
          "expand" => expand,
          "match" => %{"operator" => operator, field => content}
        }
      end)

    elasticsearch(index, %{
      "query" => %{
        "bool" => %{
          "should" => matches
        }
      }
    })
  end

  defp elasticsearch(index, %{"query" => root}) do
    {key, value} = Query.split_root(root)

    query = QueryRepository.parse(key, value, root)

    query
    |> QueryRepository.score(index)
    |> Enum.sort(fn a, b -> a.score > b.score end)
  end

  defp elasticsearch(_index, _query) do
    raise "Root object must have a query element"
  end

  defp flatten_document(document, prefix \\ "") do
    Enum.reduce(document, %{}, fn
      {key, value}, transformed when is_map(value) ->
        mapped = flatten_document(value, "#{prefix}#{key}.")
        Map.merge(transformed, mapped)

      {key, value}, transformed ->
        Map.put(transformed, "#{prefix}#{key}", value)
    end)
  end

  defp persist(fields, ref, documents, persist_fn) do
    tasks_opt = [ordered: false]

    Task.async_stream(
      documents,
      fn document ->
        document = flatten_document(document)
        save(fields, ref, document, persist_fn)
      end,
      tasks_opt
    )
    |> Stream.run()
  end

  defp save(fields, ref, document, callback) do
    Enum.each(fields, fn {attribute, field} ->
      if document[attribute] do
        data = [
          %{id: document[ref], content: document[attribute]}
        ]

        callback.(field, data)
      end
    end)
  end
end
