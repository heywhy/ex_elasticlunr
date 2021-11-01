defmodule Elasticlunr.Dsl.BoolQuery do
  @moduledoc false
  use Elasticlunr.Dsl.Query

  alias Elasticlunr.Index
  alias Elasticlunr.Dsl.{Query}

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
      rewritten: Keyword.get(opts, :must, false),
      minimum_should_match: Keyword.get(opts, :minimum_should_match, 1)
    }

    struct!(__MODULE__, attrs)
  end

  @impl true
  def score(%__MODULE__{}, %Index{} = _index) do
    []
  end

  @impl true
  def parse(options, _query_options, repo) do
    default_mapper = fn query ->
      case Query.split_root(query) do
        {key, value} ->
          repo.parse(key, value, query)

        _ ->
          repo.parse(:match_all, [])
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
    case Keyword.get(options, :should) do
      nil ->
        opts

      should when is_list(should) ->
        should =
          should
          |> Enum.map(mapper)

        Keyword.put([], :should, should)
    end
  end

  defp patch_options(opts, :filter, options, mapper) do
    case Keyword.get(options, :filter) do
      nil ->
        opts

      filter when is_list(filter) ->
        filter = Enum.map(filter, mapper)
        Keyword.put(opts, :filter, filter)
    end
  end

  defp patch_options(opts, :must, options, repo) do
    case Keyword.get(options, :must) do
      nil ->
        opts

      must when is_list(must) ->
        {key, options} = Query.split_root(must)
        must = repo.parse(key, options, must)

        Keyword.put(opts, :must, must)
    end
  end

  defp patch_options(opts, :must_not, options, repo) do
    case Keyword.get(options, :must_not) do
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
    |> Keyword.get(:minimum_should_match)
    |> case do
      nil ->
        opts

      value ->
        value <= Keyword.get(opts, :should) |> Enum.count()
    end
    |> case do
      true ->
        minimum_should_match = Keyword.get(options, :minimum_should_match)
        Keyword.put(opts, :minimum_should_match, minimum_should_match)

      opts ->
        opts
    end
  end
end
