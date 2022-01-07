defmodule Elasticlunr.Dsl.BoolQuery do
  use Elasticlunr.Dsl.Query

  alias Elasticlunr.Index
  alias Elasticlunr.Dsl.{NotQuery, Query, QueryRepository}

  defstruct ~w[rewritten should must must_not filter minimum_should_match]a

  @type t :: %__MODULE__{
          filter: Query.clause(),
          should: Query.clause(),
          must: nil | Query.clause(),
          must_not: nil | Query.clause(),
          rewritten: boolean(),
          minimum_should_match: integer()
        }

  @spec new(keyword) :: t()
  def new(opts) do
    attrs = %{
      should: Keyword.get(opts, :should, []),
      must: Keyword.get(opts, :must),
      must_not: Keyword.get(opts, :must_not),
      filter: Keyword.get(opts, :filter),
      rewritten: Keyword.get(opts, :rewritten, false),
      minimum_should_match: extract_minimum_should_match(opts)
    }

    struct!(__MODULE__, attrs)
  end

  @impl true
  def rewrite(
        %__MODULE__{
          filter: filter,
          must: must,
          must_not: must_not,
          should: should,
          minimum_should_match: minimum_should_match
        },
        %Index{} = index
      ) do
    should =
      should
      |> Kernel.||([])
      |> Enum.map(&QueryRepository.rewrite(&1, index))

    must =
      case must do
        nil ->
          nil

        mod when is_struct(mod) ->
          QueryRepository.rewrite(mod, index)
      end

    filters = filter || []

    filters =
      case must_not do
        nil ->
          filters

        must_not when is_struct(must_not) ->
          query =
            must_not
            |> QueryRepository.rewrite(index)
            |> NotQuery.new()

          [query] ++ filters
      end
      |> Enum.map(&QueryRepository.rewrite(&1, index))

    opts = [
      must: must,
      should: should,
      filter: filters,
      rewritten: true,
      minimum_should_match: minimum_should_match
    ]

    new(opts)
  end

  @impl true
  def score(%__MODULE__{rewritten: false} = query, %Index{} = index, options) do
    query
    |> rewrite(index)
    |> score(index, options)
  end

  def score(
        %__MODULE__{
          must: must,
          filter: filter,
          should: should,
          minimum_should_match: minimum_should_match
        },
        %Index{} = index,
        _options
      ) do
    filter_results = filter_result(filter, index)
    filter_results = filter_must(must, filter_results, index)

    {docs, filtered} =
      case filter_results do
        false ->
          {%{}, nil}

        value ->
          Enum.reduce(value, {%{}, []}, fn %{ref: ref, score: score}, {docs, filtered} ->
            filtered = [ref] ++ filtered

            doc = %{
              ref: ref,
              matched: 0,
              positions: %{},
              score: score || 0
            }

            docs = Map.put(docs, ref, doc)

            {docs, filtered}
          end)
      end

    {docs, _filtered} =
      should
      |> Enum.reduce({docs, filtered}, fn query, {docs, filtered} ->
        opts =
          case filtered do
            nil ->
              []

            filtered ->
              [filtered: filtered]
          end

        results = QueryRepository.score(query, index, opts)

        docs =
          results
          |> Enum.reduce(docs, fn doc, docs ->
            ob =
              Map.get(docs, doc.ref, %{
                ref: doc.ref,
                score: 0,
                matched: 0,
                positions: %{}
              })

            %{matched: matched, score: score, positions: positions} = ob

            # credo:disable-for-lines:3
            positions =
              Map.get(doc, :positions, %{})
              |> Enum.reduce(positions, fn {field, tokens}, positions ->
                p = Map.get(positions, field, [])
                p = Enum.reduce(tokens, p, &(&2 ++ [&1]))
                Map.put(positions, field, p)
              end)

            doc_score = Map.get(doc, :score, 0)

            ob = %{ob | positions: positions, matched: matched + 1, score: score + doc_score}

            Map.put(docs, doc.ref, ob)
          end)

        {docs, filtered}
      end)

    docs
    |> Stream.map(&elem(&1, 1))
    |> Stream.filter(fn doc -> doc.matched >= minimum_should_match && doc.score > 0 end)
  end

  defp filter_result(nil, _index), do: false
  defp filter_result([], _index), do: false

  defp filter_result(filter, index) do
    filter
    |> Enum.reduce(false, fn query, acc ->
      q =
        case acc do
          false ->
            []

          val ->
            [filtered: Enum.map(val, & &1.ref)]
        end

      QueryRepository.filter(query, index, q)
    end)
  end

  defp filter_must(nil, filter_results, _index), do: filter_results

  defp filter_must(must_query, filter_results, index) when is_struct(must_query) do
    q =
      case filter_results do
        false ->
          []

        results ->
          [filtered: Enum.map(results, & &1.ref)]
      end

    QueryRepository.score(must_query, index, q)
  end

  @impl true
  def parse(options, _query_options, repo) do
    default_mapper = fn query ->
      case Query.split_root(query) do
        {key, value} ->
          repo.parse(key, value, query)

        _ ->
          repo.parse("match_all", [])
      end
    end

    []
    |> patch_options(:should, options, default_mapper)
    |> patch_options(:filter, options, default_mapper)
    |> patch_options(:must, options, repo)
    |> patch_options(:must_not, options, repo)
    |> patch_options(:minimum_should_match, options)
    |> __MODULE__.new()
  end

  defp patch_options(opts, :should, options, mapper) do
    case Map.get(options, "should") do
      nil ->
        opts

      should when is_list(should) ->
        should =
          should
          |> Enum.map(mapper)

        Keyword.put(opts, :should, should)

      should ->
        Keyword.put(opts, :should, [mapper.(should)])
    end
  end

  defp patch_options(opts, :filter, options, mapper) do
    case Map.get(options, "filter") do
      nil ->
        opts

      filter when is_list(filter) ->
        filter = Enum.map(filter, mapper)
        Keyword.put(opts, :filter, filter)

      filter ->
        Keyword.put(opts, :filter, [mapper.(filter)])
    end
  end

  defp patch_options(opts, :must, options, repo) do
    case Map.get(options, "must") do
      nil ->
        opts

      must when is_map(must) ->
        {key, options} = Query.split_root(must)
        must = repo.parse(key, options, must)

        Keyword.put(opts, :must, must)
    end
  end

  defp patch_options(opts, :must_not, options, repo) do
    case Map.get(options, "must_not") do
      nil ->
        opts

      must_not ->
        {key, options} = Query.split_root(must_not)

        q = repo.parse(key, options, must_not)

        Keyword.put(opts, :must_not, q)
    end
  end

  defp patch_options(opts, :minimum_should_match, options) do
    options
    |> Map.get("minimum_should_match")
    |> case do
      nil ->
        opts

      value when is_integer(value) ->
        value <= Keyword.get(opts, :should) |> Enum.count()
    end
    |> case do
      true ->
        minimum_should_match = Map.get(options, "minimum_should_match")
        Keyword.put(opts, :minimum_should_match, minimum_should_match)

      _ ->
        opts
    end
  end

  defp extract_minimum_should_match(opts) do
    default_value =
      case not is_empty_clause?(opts[:should]) and
             (is_empty_clause?(opts[:must]) or is_empty_clause?(opts[:filter])) do
        true -> 1
        false -> 0
      end

    Keyword.get(opts, :minimum_should_match, default_value)
  end

  defp is_empty_clause?(nil), do: true
  defp is_empty_clause?(list) when is_list(list), do: Enum.empty?(list)
  defp is_empty_clause?(%{}), do: false
end
