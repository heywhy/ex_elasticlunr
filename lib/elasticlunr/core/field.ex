defmodule Elasticlunr.Field do
  alias Elasticlunr.{Pipeline, Token, Utils}

  @fields ~w[pipeline query_pipeline store store_positions flnorm tf idf ids documents terms on_conflict]a

  @enforce_keys @fields
  defstruct @fields

  @type flnorm :: integer() | float()

  @type t :: %__MODULE__{
          pipeline: Pipeline.t() | nil,
          query_pipeline: Pipeline.t() | nil,
          store: boolean(),
          store_positions: boolean(),
          flnorm: flnorm(),
          tf: map(),
          idf: map(),
          terms: map(),
          documents: map(),
          ids: map(),
          on_conflict: atom()
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
    attrs = %{
      ids: %{},
      tf: %{},
      idf: %{},
      flnorm: 1,
      terms: %{},
      documents: %{},
      pipeline: Keyword.get(opts, :pipeline),
      on_conflict: Keyword.get(opts, :on_conflict),
      store: Keyword.get(opts, :store_documents, false),
      query_pipeline: Keyword.get(opts, :query_pipeline),
      store_positions: Keyword.get(opts, :store_positions, false)
    }

    struct!(__MODULE__, attrs)
  end

  @spec all(t()) :: list(document_ref())
  def all(%__MODULE__{ids: ids}), do: Map.keys(ids)

  @spec term_frequency(t(), binary()) :: map()
  def term_frequency(%__MODULE__{tf: tf}, term), do: Map.get(tf, term)

  @spec has_token(t(), binary()) :: boolean()
  def has_token(%__MODULE__{idf: idf}, term) do
    case Map.get(idf, term) do
      nil ->
        false

      count ->
        count > 0
    end
  end

  @spec get_token(t(), binary()) :: token_info() | nil
  def get_token(%__MODULE__{idf: idf, tf: tf, flnorm: flnorm}, term) do
    case Map.get(idf, term) do
      nil ->
        nil

      _ ->
        %{
          term: term,
          flnorm: flnorm,
          tf: Map.get(tf, term),
          idf: Map.get(idf, term),
          documents: Map.get(tf, term, %{}) |> Map.keys()
        }
    end
  end

  @spec set_query_pipeline(t(), module()) :: t()
  def set_query_pipeline(%__MODULE__{} = field, pipeline) do
    %{field | query_pipeline: pipeline}
  end

  @spec add(t(), list(document())) :: t()
  def add(%__MODULE__{ids: ids, store: store, pipeline: pipeline} = field, documents) do
    Enum.reduce(documents, field, fn %{id: id, content: content}, field ->
      if Map.has_key?(ids, id) do
        handle_conflict(field, %{id: id, content: content})
      else
        field =
          case store do
            false ->
              field

            true ->
              %{documents: documents} = field
              %{field | documents: Map.put(documents, id, content)}
          end

        %{ids: ids} = field
        field = %{field | ids: Map.put(ids, id, true)}
        tokens = Pipeline.run(pipeline, content)

        update_field_stats(field, id, tokens)
      end
    end)
    |> recalculate_idf()
  end

  @spec set_token(t(), binary(), map()) :: t()
  def set_token(%__MODULE__{} = field, term, documents) do
    Enum.reduce(documents, field, fn {doc_id, opts}, field ->
      ct = :math.pow(opts.tf, 2)

      %{ids: ids, tf: tf, terms: terms} = field
      term_map = Map.get(terms, term, %{})

      term_map =
        Map.put(term_map, doc_id, %{
          total: trunc(ct),
          positions: opts[:positions] || []
        })

      terms = Map.put(terms, term, term_map)

      tf_map = Map.get(tf, term, %{})
      tf_map = Map.put(tf_map, doc_id, opts.tf)

      tf = Map.put(tf, term, tf_map)

      %{field | terms: terms, tf: tf, ids: Map.put(ids, doc_id, true)}
    end)
    |> recalculate_idf()
  end

  defp update_field_stats(field, id, tokens) do
    tokens
    |> Stream.map(&to_token/1)
    |> Enum.reduce(field, fn token, field ->
      %Token{token: term} = token
      %{tf: tf, terms: terms} = field

      terms = Map.put_new(terms, term, %{})

      term_attrs =
        terms
        |> Map.get(term)
        |> Map.put_new(id, %{
          total: 0,
          positions: []
        })

      attr = Map.get(term_attrs, id)
      %{total: total, positions: positions} = attr

      positions =
        case Token.get_position(token) do
          nil ->
            positions

          position ->
            positions ++ [position]
        end

      total = total + 1
      term_attrs = Map.put(term_attrs, id, %{attr | positions: positions, total: total})

      terms = Map.put(terms, term, term_attrs)

      tf =
        tf
        |> Map.put_new(term, %{})
        |> put_in([term, id], :math.sqrt(total))

      %{field | tf: tf, terms: terms}
    end)
  end

  @spec update(t(), list(document())) :: t()
  def update(%__MODULE__{} = field, documents) do
    document_ids = Enum.map(documents, & &1.id)

    field
    |> remove(document_ids)
    |> add(documents)
  end

  @spec remove(t(), list(document_ref())) :: t()
  def remove(%__MODULE__{terms: terms} = field, document_ids) do
    trim_field = fn field, key ->
      %{tf: tf, idf: idf, terms: terms} = field

      if Enum.empty?(terms[key]) do
        %{
          field
          | tf: Map.delete(tf, key),
            idf: Map.delete(idf, key),
            terms: Map.delete(terms, key)
        }
      else
        field
      end
    end

    clean_up_terms = fn {key, value}, id, field ->
      case Map.get(value, id) do
        nil ->
          field

        _ ->
          %{tf: tf, terms: terms} = field

          tf_value = Map.get(tf, key)
          terms = Map.put(terms, key, Map.delete(value, id))
          tf = Map.put(tf, key, Map.delete(tf_value, id))
          field = %{field | tf: tf, terms: terms}

          trim_field.(field, key)
      end
    end

    document_ids
    |> Enum.reduce(field, fn document_id, %{ids: ids, documents: documents} = field ->
      documents = Map.delete(documents, document_id)
      ids = Map.delete(ids, document_id)

      Enum.reduce(terms, %{field | ids: ids, documents: documents}, fn term, field ->
        clean_up_terms.(term, document_id, field)
      end)
    end)
    |> recalculate_idf()
  end

  @spec analyze(t(), any(), keyword) :: Token.t() | list(Token.t())
  def analyze(%__MODULE__{pipeline: pipeline, query_pipeline: query_pipeline}, str, options) do
    case Keyword.get(options, :is_query, false) && not is_nil(query_pipeline) do
      true ->
        Pipeline.run(query_pipeline, str)

      false ->
        Pipeline.run(pipeline, str)
    end
  end

  @spec terms(t(), keyword()) :: any()
  def terms(%__MODULE__{terms: terms} = field, query) do
    fuzz = Keyword.get(query, :fuzziness) || 0
    msm = Keyword.get(query, :minimum_should_match) || 1

    matching_docs =
      query
      |> Keyword.get(:terms)
      |> Stream.map(fn
        %Regex{} = re -> re
        val -> to_token(val)
      end)
      |> Enum.reduce(%{}, fn
        %Regex{} = re, matching_docs ->
          matched_terms =
            terms
            |> Map.keys()
            |> Stream.filter(&Regex.match?(re, &1))

          Enum.reduce(matched_terms, matching_docs, fn term, matching_docs ->
            ids = Map.get(terms, term) |> Map.keys()

            filter_ids(field, ids, term, matching_docs, query)
          end)

        %Token{token: term}, matching_docs ->
          matching_docs =
            case fuzz == 0 && Map.has_key?(terms, term) do
              true ->
                ids = Map.keys(Map.get(terms, term))

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

  @spec all_tokens(Elasticlunr.Field.t()) :: Enum.t()
  def all_tokens(%__MODULE__{tf: tf, idf: idf, flnorm: flnorm, terms: terms}) do
    Map.keys(terms)
    |> Stream.map(fn term ->
      tf = Map.get(tf, term, %{})

      %{
        tf: tf,
        term: term,
        terms: Map.get(terms, term),
        idf: Map.get(idf, term),
        norm: flnorm,
        documents: Map.keys(tf)
      }
    end)
  end

  defp handle_conflict(%{on_conflict: :index} = field, document) do
    update(field, [document])
  end

  defp handle_conflict(%{on_conflict: :error}, %{id: id}) do
    raise "Document id #{id} already exists in the index"
  end

  defp handle_conflict(%{on_conflict: :ignore} = field, _document), do: field

  defp recalculate_idf(%{idf: idf, ids: ids, terms: terms} = field) do
    terms_length = Enum.count(terms)

    flnorm =
      case terms_length > 0 do
        true ->
          1 / :math.sqrt(terms_length)

        false ->
          0
      end

    ids_length = Enum.count(ids)

    idf =
      terms
      |> Map.keys()
      |> Stream.map(&to_token/1)
      |> Enum.reduce(idf, fn %Token{token: token}, idf ->
        token_length =
          terms
          |> Map.get(token)
          |> Enum.count()
          |> Kernel.+(1)

        value = 1 + :math.log10(ids_length / token_length)
        Map.put(idf, token, value)
      end)

    %{field | idf: idf, flnorm: flnorm}
  end

  defp filter_ids(field, ids, term, matching_docs, query) do
    docs = Keyword.get(query, :docs)

    case docs do
      docs when is_list(docs) ->
        Enum.filter(ids, &(&1 in docs))

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

  defp match_with_fuzz(%{terms: terms} = field, term, fuzz, query, matching_docs) when fuzz > 0 do
    terms
    |> Map.keys()
    |> Enum.reduce(matching_docs, fn key, matching_docs ->
      if Utils.levenshtein_distance(key, term) <= fuzz do
        ids = Map.keys(Map.get(terms, key))
        filter_ids(field, ids, key, matching_docs, query)
      else
        matching_docs
      end
    end)
  end

  defp match_with_fuzz(_field, _term, _fuzz, _query, matching_docs), do: matching_docs

  defp extract_matched(
         %{idf: idf, tf: tf, terms: terms, flnorm: flnorm, store: store, documents: documents},
         term,
         id
       ) do
    positions = get_in(terms, [term, id, :positions])
    tf = get_in(tf, [term, id])
    idf = Map.get(idf, term)

    content =
      case store && Map.has_key?(documents, id) do
        true ->
          Map.get(documents, id)

        false ->
          nil
      end

    %{
      tf: tf,
      ref: id,
      idf: idf,
      norm: flnorm,
      content: content,
      positions: positions
    }
  end

  defp to_token(%Token{} = token), do: token
  defp to_token(token), do: Token.new(token)
end
