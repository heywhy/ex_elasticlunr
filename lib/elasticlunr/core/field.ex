# credo:disable-for-this-file
defmodule Elasticlunr.Field do
  alias Elasticlunr.{DB, Pipeline, Token}

  @fields ~w[db name pipeline query_pipeline store store_positions flnorm tf idf ids documents terms]a

  @enforce_keys @fields
  defstruct @fields

  @type flnorm :: integer() | float()

  @type t :: %__MODULE__{
          db: DB.t(),
          name: String.t(),
          pipeline: Pipeline.t() | nil,
          query_pipeline: Pipeline.t() | nil,
          store: boolean(),
          store_positions: boolean(),
          flnorm: flnorm(),
          tf: map(),
          idf: map(),
          terms: map(),
          documents: map(),
          ids: map()
        }

  @spec new(keyword) :: t()
  def new(opts) do
    attrs = %{
      ids: %{},
      tf: %{},
      idf: %{},
      flnorm: 1,
      terms: %{},
      documents: %{},
      db: Keyword.get(opts, :db),
      name: Keyword.get(opts, :name),
      pipeline: Keyword.get(opts, :pipeline),
      store: Keyword.get(opts, :store_documents, false),
      query_pipeline: Keyword.get(opts, :query_pipeline),
      store_positions: Keyword.get(opts, :store_positions, false)
    }

    struct!(__MODULE__, attrs)
  end

  @spec add(t(), list(map())) :: any()
  def add(%__MODULE__{pipeline: pipeline} = field, documents) do
    Enum.each(documents, fn %{id: id, content: content} ->
      if id_exists(field, id) do
        raise "Document id #{id} already exists in the index"
      end

      tokens = Pipeline.run(pipeline, content)

      add_id(field, id)
      update_field_stats(field, id, tokens)
    end)

    recalculate_idf(field)
  end

  @spec length(t(), atom()) :: pos_integer()
  def length(%__MODULE__{} = field, :ids) do
    fun = [{{{:field_ids, :"$1", :_}}, [{:==, :"$1", field.name}], [true]}]
    DB.select_count(field.db, fun)
  end

  @spec length(t(), atom(), String.t()) :: pos_integer()
  def length(%__MODULE__{} = field, :term, term) do
    fun = [
      {{{:field_term, :"$1", :"$2", :_}, :_},
       [{:andalso, {:==, :"$1", field.name}, {:==, :"$2", term}}], [true]}
    ]

    DB.select_count(field.db, fun)
  end

  defp recalculate_idf(field) do
    terms = terms_lookup(field)
    terms_length = Enum.count(terms)

    ids_length = length(field, :ids)

    flnorm =
      case terms_length > 0 do
        true ->
          1 / :math.sqrt(terms_length)

        false ->
          0
      end

    :ok =
      Stream.each(terms, fn
        {{:field_term, _, term, _id}, _attrs} ->
          count = length(field, :term, term) + 1
          value = 1 + :math.log10(ids_length / count)

          true = DB.insert(field.db, {{:field_idf, field.name, term}, value})
      end)
      |> Stream.run()

    true = DB.insert(field.db, {{:field_flnorm, field.name, flnorm}})
  end

  defp update_field_stats(%{db: db, name: name} = field, id, tokens) do
    Enum.each(tokens, fn token ->
      %Token{token: term} = token

      term_attrs = term_lookup(field, term, id)

      term_attrs =
        case Token.get_position(token) do
          nil ->
            term_attrs

          position ->
            %{term_attrs | positions: term_attrs.positions ++ [position]}
        end

      term_attrs = %{term_attrs | total: term_attrs.total + 1}

      true = DB.insert(db, {{:field_term, name, term, id}, term_attrs})
      true = DB.insert(db, {{:field_tf, name, term, id}, :math.sqrt(term_attrs.total)})
    end)
  end

  defp add_id(%{db: db, name: name}, id) do
    true = DB.insert(db, {{:field_ids, name, id}})
  end

  defp id_exists(%{db: db, name: field}, id) do
    fun = [
      {{{:field_ids, :"$1", :"$2"}}, [{:andalso, {:==, :"$1", field}, {:==, :"$2", id}}], [true]}
    ]

    DB.select_count(db, fun) > 0
  end

  defp term_lookup(%{db: db, name: field}, term, id) do
    case DB.match_object(db, {{:field_term, field, term, id}, :_}) do
      [] ->
        %{total: 0, positions: []}

      [{_, attrs}] ->
        attrs
    end
  end

  defp terms_lookup(%{db: db, name: field}) do
    case DB.match_object(db, {{:field_term, field, :_, :_}, :_}) do
      [] ->
        %{total: 0, positions: []}

      terms ->
        terms
    end
  end

  defp tf_lookup(%{db: db, name: field}, term, id) do
    case DB.match_object(db, {{:field_tf, field, term, id}, :_}) do
      [] ->
        %{total: 0, positions: []}

      [{_, attrs}] ->
        attrs
    end
  end
end
