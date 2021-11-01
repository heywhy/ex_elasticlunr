defmodule Elasticlunr.Dsl.MatchQuery do
  @moduledoc false
  use Elasticlunr.Dsl.Query

  defstruct ~w[expand field query boost fuzziness min_match operator]a
  @type t :: %__MODULE__{boost: integer()}

  def new(opts) do
    attrs = %{
      expand: Keyword.get(opts, :expand, false),
      field: Keyword.get(opts, :field, ""),
      query: Keyword.get(opts, :query, ""),
      boost: Keyword.get(opts, :boost, 1),
      fuzziness: Keyword.get(opts, :fuzziness, 0),
      min_match: Keyword.get(opts, :minimum_must_match, 1),
      operator: Keyword.get(opts, :operator, "or")
    }

    struct!(__MODULE__, attrs)
  end

  @impl true
  def parse(options, query_options, repo) do
    fields =
      options
      |> Enum.filter(fn
        {key, _val} when key in ~w[fuzziness operator]a ->
          false

        _ ->
          true
      end)

    fuzziness = Keyword.get(options, :fuzziness)
    operator = Keyword.get(options, :operator, "or")
    expand = Keyword.get(query_options, :expand, false)

    cond do
      Enum.empty?(fields) ->
        repo.parse(:match_all, [], [])

      Enum.count(fields) > 1 ->
        minimum_should_match =
          case operator == "and" do
            true ->
              Enum.count(fields)

            false ->
              1
          end

        should =
          fields
          |> Enum.map(fn {field, content} ->
            match =
              [
                operator: operator,
                fuzziness: fuzziness
              ]
              |> Keyword.put(field, content)

            [match: match, expand: expand]
          end)

        repo.parse(:bool,
          should: should,
          minimum_should_match: minimum_should_match
        )

      true ->
        [{field, content}] = fields

        minimum_should_match =
          case operator == "and" do
            true ->
              0

            false ->
              1
          end

        __MODULE__.new(
          field: field,
          query: content,
          fuzziness: fuzziness,
          expand: expand,
          operator: operator,
          minimum_must_match: minimum_should_match
        )
    end
  end
end
