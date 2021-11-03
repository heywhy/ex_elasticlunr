defmodule Elasticlunr.DslTest do
  use ExUnit.Case

  alias Elasticlunr.{Index, Pipeline, Token}
  alias Elasticlunr.Dsl.{MatchAllQuery, TermsQuery}

  setup context do
    callback = fn
      %Token{} = token ->
        token

      str ->
        str
        |> String.split(" ")
        |> Enum.map(&Token.new(&1))
    end

    pipeline = Pipeline.new([callback])

    index =
      [fields: [content: [pipeline: pipeline]]]
      |> Index.new()
      |> Index.add_documents([
        %{id: 1, content: "The quick fox jumped over the lazy dog"},
        %{
          id: 2,
          content:
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas viverra enim non purus rutrum porta ut non urna. Nullam eu ante eget nisi laoreet pretium. Curabitur varius velit vel viverra facilisis. Pellentesque et condimentum mauris. Quisque faucibus varius interdum. Fusce cursus pretium tempus. Ut gravida tortor et mi dignissim sagittis. Aliquam ullamcorper dignissim arcu sollicitudin fermentum. Nunc elementum tortor ex, sit amet posuere lectus accumsan quis. Vivamus sit amet eros blandit, sagittis quam at, vulputate felis. Ut faucibus pretium feugiat. Fusce diam felis, euismod ac tellus id, blandit venenatis dolor. Nullam porttitor suscipit diam, a feugiat dui pharetra at."
        },
        %{id: 3, content: "Lorem dog"}
      ])

    Map.put(context, :index, index)
  end

  describe "primitives ::" do
    test "[match_all] correctly operates match_all query", %{index: index} do
      query = MatchAllQuery.new()

      assert result = MatchAllQuery.score(query, index, [])
      assert Enum.count(result) == 3

      for %{score: score} <- result do
        assert score == 1
      end
    end

    test "[terms] performs base functionality", %{index: index} do
      query =
        TermsQuery.new(
          field: :content,
          terms: ["fox"]
        )

      assert result = TermsQuery.score(query, index, [])
      assert Enum.count(result) == 1
      assert [%{ref: 1}] = result
    end

    test "[terms] boost", %{index: index} do
      non_boost_query =
        TermsQuery.new(
          field: :content,
          terms: ["fox"]
        )

      boost_query =
        TermsQuery.new(
          field: :content,
          terms: ["fox"],
          boost: 2
        )

      assert boost_result = TermsQuery.score(boost_query, index, [])
      assert non_boost_result = TermsQuery.score(non_boost_query, index, [])
      assert Enum.count(boost_result) == Enum.count(non_boost_result)
      assert [%{score: score_1}] = boost_result
      assert [%{score: score_2}] = non_boost_result
      assert score_1 == score_2 * 2
    end
  end
end
