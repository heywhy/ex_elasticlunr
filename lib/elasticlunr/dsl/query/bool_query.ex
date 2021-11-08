defmodule Elasticlunr.Dsl.BoolQuery do
  use Elasticlunr.Dsl.Query

  alias Elasticlunr.Index
  alias Elasticlunr.Dsl.{NotQuery, Query, QueryRepository}

  defstruct ~w[rewritten should must must_not filter minimum_should_match]a

  @type t :: %__MODULE__{
          should: keyword(),
          must: boolean(),
          must_not: boolean(),
          rewritten: boolean(),
          minimum_should_match: integer()
        }

  def new(opts) do
    attrs = %{
      should: Keyword.get(opts, :should, []),
      must: Keyword.get(opts, :must, false),
      must_not: Keyword.get(opts, :must_not, false),
      filter: Keyword.get(opts, :filter),
      rewritten: Keyword.get(opts, :rewritten, false),
      minimum_should_match: Keyword.get(opts, :minimum_should_match, 1)
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
        false ->
          false

        mod when is_struct(mod) ->
          QueryRepository.rewrite(mod, index)
      end

    filters = filter || []

    filters =
      case must_not do
        false ->
          filters

        must_not when is_struct(must_not) ->
          query =
            must_not
            |> QueryRepository.rewrite(index)
            |> NotQuery.new()

          filters ++ [query]
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

            # credo:disable-for-lines:2
            positions =
              Enum.reduce(doc.positions, positions, fn {field, tokens}, positions ->
                p = Map.get(positions, field, [])
                p = Enum.reduce(tokens, p, &(&2 ++ [&1]))
                Map.put(positions, field, p)
              end)

            ob = %{ob | positions: positions, matched: matched + 1, score: score + doc.score}

            Map.put(docs, doc.ref, ob)
          end)

        {docs, filtered}
      end)

    docs
    |> Map.values()
    |> Enum.filter(fn doc -> doc.matched >= minimum_should_match && doc.score > 0 end)
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

  defp filter_must(false, filter_results, _index), do: filter_results

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

      value ->
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
end
