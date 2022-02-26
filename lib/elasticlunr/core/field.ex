defmodule Elasticlunr.Field do
  alias Elasticlunr.{DB, Pipeline, Token, Utils}

  @fields ~w[db name pipeline query_pipeline store store_positions]a

  @enforce_keys @fields
  defstruct @fields

  @type flnorm :: integer() | float()

  @type t :: %__MODULE__{
          db: DB.t(),
          name: String.t(),
          pipeline: Pipeline.t() | nil,
          query_pipeline: Pipeline.t() | nil,
          store: boolean(),
          store_positions: boolean()
        }

  @type document_ref :: atom() | binary()
  @type document :: %{id: document_ref(), content: binary()}
  @type token_info :: %{
          term: term,
          tf: map(),
          idf: map(),
          flnorm: flnorm(),
          documents: map()
        }

  @spec new(keyword) :: t()
  def new(opts) do
    attrs = [
      db: Keyword.get(opts, :db),
      name: Keyword.get(opts, :name),
      pipeline: Keyword.get(opts, :pipeline),
      store: Keyword.get(opts, :store_documents, false),
      query_pipeline: Keyword.get(opts, :query_pipeline),
      store_positions: Keyword.get(opts, :store_positions, false)
    ]

    struct!(__MODULE__, attrs)
  end

  @spec documents(t()) :: list(document_ref())
  def documents(%__MODULE__{db: db, name: name}) do
    case DB.match_object(db, {{:field_ids, name, :_}}) do
      [] ->
        []

      ids ->
        Stream.map(ids, fn {{:field_ids, _, id}} -> id end)
    end
  end

  @spec term_frequency(t(), binary()) :: map()
  def term_frequency(%__MODULE__{} = field, term) do
    tf_lookup(field, term)
  end

  @spec has_token(t(), binary()) :: boolean()
  def has_token(%__MODULE__{} = field, term) do
    DB.member?(field.db, {:field_idf, field.name, term})
  end

  @spec get_token(t(), binary()) :: token_info() | nil
  def get_token(%__MODULE__{} = field, term) do
    case idf_lookup(field, term) do
      nil ->
        nil

      _ ->
        flnorm = flnorm_lookup(field)
        to_field_token(field, term, flnorm)
    end
  end

  @spec set_query_pipeline(t(), module()) :: t()
  def set_query_pipeline(%__MODULE__{} = field, pipeline) do
    %{field | query_pipeline: pipeline}
  end

  @spec add(t(), list(document())) :: t()
  def add(%__MODULE__{pipeline: pipeline} = field, documents) do
    Enum.each(documents, fn %{id: id, content: content} ->
      unless DB.member?(field.db, {:field_ids, field.name, id}) do
        tokens = Pipeline.run(pipeline, content)

        add_id(field, id)
        update_field_stats(field, id, tokens)
      end
    end)

    recalculate_idf(field)
  end

  @spec length(t(), atom()) :: pos_integer()
  def length(%__MODULE__{db: db, name: name}, :ids) do
    fun = [{{{:field_ids, name, :_}}, [], [true]}]
    DB.select_count(db, fun)
  end

  @spec length(t(), atom(), String.t()) :: pos_integer()
  def length(%__MODULE__{db: db, name: name}, :term, term) do
    fun = [
      {{{:field_term, name, term, :_}, :_}, [], [true]}
    ]

    DB.select_count(db, fun)
  end

  def length(%__MODULE__{db: db, name: name}, :tf, term) do
    fun = [
      {{{:field_tf, name, term, :_}, :_}, [], [true]}
    ]

    DB.select_count(db, fun)
  end

  def length(%__MODULE__{db: db, name: name}, :idf, term) do
    fun = [
      {{{:field_idf, name, term}, :_}, [], [true]}
    ]

    DB.select_count(db, fun)
  end

  @spec update(t(), list(document())) :: t()
  def update(%__MODULE__{} = field, documents) do
    document_ids = Enum.map(documents, & &1.id)

    field
    |> remove(document_ids)
    |> add(documents)
  end

  @spec remove(t(), list(document_ref())) :: t()
  def remove(%__MODULE__{db: db, name: name} = field, document_ids) do
    Enum.each(document_ids, fn id ->
      true = DB.match_delete(db, {{:field_term, name, :_, id}, :_})
      true = DB.match_delete(db, {{:field_tf, name, :_, id}, :_})
      true = DB.match_delete(db, {{:field_idf, name, :_}, :_})
      true = DB.delete(db, {:field_ids, name, id})
    end)

    recalculate_idf(field)
  end

  @spec analyze(t(), any(), keyword) :: list(Token.t())
  def analyze(%__MODULE__{pipeline: pipeline, query_pipeline: query_pipeline}, content, options) do
    case Keyword.get(options, :is_query, false) && not is_nil(query_pipeline) do
      true ->
        Pipeline.run(query_pipeline, content)

      false ->
        Pipeline.run(pipeline, content)
    end
  end

  @spec terms(t(), keyword()) :: any()
  def terms(%__MODULE__{} = field, query) do
    fuzz = Keyword.get(query, :fuzziness, 0)
    msm = Keyword.get(query, :minimum_should_match, 1)

    terms = terms_lookup(field)

    matching_docs =
      Stream.map(query[:terms], fn
        %Regex{} = re -> re
        val -> to_token(val)
      end)
      |> Enum.reduce(%{}, fn
        %Regex{} = re, matching_docs ->
          matched_terms = Stream.filter(terms, &Regex.match?(re, elem(&1, 0)))

          Enum.reduce(matched_terms, matching_docs, fn {term, _, _}, matching_docs ->
            ids = matching_ids(field, term)

            filter_ids(field, ids, term, matching_docs, query)
          end)

        %Token{token: term}, matching_docs ->
          matching_docs =
            case fuzz == 0 && length(field, :term, term) > 0 do
              true ->
                ids = matching_ids(field, term)

                filter_ids(field, ids, term, matching_docs, query)

              false ->
                matching_docs
            end

          match_with_fuzz(field, term, fuzz, query, matching_docs)
      end)

    if msm <= 1 do
      matching_docs
    else
      matching_docs
      |> Stream.filter(fn {_key, content} ->
        Enum.count(content) >= msm
      end)
      |> Enum.into(%{})
    end
  end

  @spec tokens(Elasticlunr.Field.t()) :: Enumerable.t()
  def tokens(%__MODULE__{} = field) do
    flnorm = flnorm_lookup(field)

    unique_terms_lookup(field)
    |> Stream.map(fn {term, _, _} ->
      to_field_token(field, term, flnorm)
    end)
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

  defp matched_documents_for_term(%{db: db, name: name}, term) do
    db
    |> DB.match_object({{:field_term, name, term, :_}, :_})
    |> Stream.map(fn {{:field_term, _, _, id}, _} -> id end)
  end

  defp term_lookup(%{db: db, name: name}, term, id) do
    case DB.match_object(db, {{:field_term, name, term, id}, :_}) do
      [] ->
        %{total: 0, positions: []}

      [{_, attrs}] ->
        attrs
    end
  end

  defp terms_lookup(%{db: db, name: name}) do
    db
    |> DB.match_object({{:field_term, name, :_, :_}, :_})
    |> Stream.map(&termify/1)
  end

  defp terms_lookup(%{db: db, name: name}, term) do
    db
    |> DB.match_object({{:field_term, name, term, :_}, :_})
    |> Stream.map(&termify/1)
  end

  defp termify({{:field_term, _, term, id}, attrs}), do: {term, id, attrs}

  defp tf_lookup(%{db: db, name: name}, term) do
    case DB.match_object(db, {{:field_tf, name, term, :_}, :_}) do
      [] ->
        nil

      terms ->
        terms
        |> Stream.map(fn {{:field_tf, _, _, id}, count} ->
          {id, count}
        end)
    end
  end

  defp tf_lookup(%{db: db, name: name}, term, id) do
    case DB.match_object(db, {{:field_tf, name, term, id}, :_}) do
      [] ->
        nil

      [{{:field_tf, _, _, id}, count}] ->
        {id, count}
    end
  end

  defp idf_lookup(%{db: db, name: name}, term) do
    case DB.match_object(db, {{:field_idf, name, term}, :_}) do
      [] ->
        nil

      [{{:field_idf, _, _}, value}] ->
        value
    end
  end

  defp flnorm_lookup(%{db: db, name: name}) do
    case DB.lookup(db, {:field_flnorm, name}) do
      [] ->
        1

      [{{:field_flnorm, _}, value}] ->
        value
    end
  end

  defp unique_terms_lookup(field) do
    terms_lookup(field)
    |> Stream.uniq_by(&elem(&1, 0))
  end

  defp recalculate_idf(field) do
    terms = unique_terms_lookup(field)

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
      terms
      |> Task.async_stream(fn {term, _id, _attrs} ->
        count = length(field, :term, term) + 1
        value = 1 + :math.log10(ids_length / count)

        true = DB.insert(field.db, {{:field_idf, field.name, term}, value})
      end)
      |> Stream.run()

    true = DB.insert(field.db, {{:field_flnorm, field.name}, flnorm})
    field
  end

  defp filter_ids(field, ids, term, matching_docs, query) do
    docs = Keyword.get(query, :docs)

    case docs do
      docs when is_list(docs) ->
        Stream.filter(ids, &(&1 in docs))

      _ ->
        ids
    end
    |> get_matching_docs(field, term, matching_docs)
  end

  defp get_matching_docs(docs, field, term, matching_docs) do
    docs
    |> Enum.reduce(matching_docs, fn id, matching_docs ->
      matched =
        matching_docs
        |> Map.get(id, [])
        |> Kernel.++([extract_matched(field, term, id)])

      Map.put(matching_docs, id, matched)
    end)
  end

  defp match_with_fuzz(field, term, fuzz, query, matching_docs) when fuzz > 0 do
    field
    |> unique_terms_lookup()
    |> Enum.reduce(matching_docs, fn {key, _id, _attr}, matching_docs ->
      if Utils.levenshtein_distance(key, term) <= fuzz do
        ids = matching_ids(field, term)
        filter_ids(field, ids, key, matching_docs, query)
      else
        matching_docs
      end
    end)
  end

  defp match_with_fuzz(_field, _term, _fuzz, _query, matching_docs), do: matching_docs

  defp matching_ids(field, term) do
    terms_lookup(field, term)
    |> Stream.map(&elem(&1, 1))
  end

  defp get_content(_field, _id) do
    nil
  end

  defp extract_matched(field, term, id) do
    attrs = term_lookup(field, term, id)
    positions = Map.get(attrs, :positions)
    {^id, tf} = tf_lookup(field, term, id)

    %{
      tf: tf,
      ref: id,
      positions: positions,
      norm: flnorm_lookup(field),
      idf: idf_lookup(field, term),
      content: get_content(field, id)
    }
  end

  defp to_token(%Token{} = token), do: token
  defp to_token(token), do: Token.new(token)

  defp to_field_token(field, term, flnorm) do
    %{
      term: term,
      norm: flnorm,
      tf: length(field, :tf, term),
      idf: idf_lookup(field, term),
      documents: matched_documents_for_term(field, term)
    }
  end
end
