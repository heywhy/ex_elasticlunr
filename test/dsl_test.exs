defmodule Elasticlunr.DslTest do
  use ExUnit.Case

  alias Elasticlunr.{Index, Pipeline, Token}
  alias Elasticlunr.Dsl.{BoolQuery, MatchAllQuery, MatchQuery, TermsQuery}

  setup context do
    callback = fn
      %Token{} = token ->
        token

      str ->
        str
        |> String.split(" ")
        |> String.downcase()
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

  describe "match_all" do
    test "correctly operates match_all query", %{index: index} do
      query = MatchAllQuery.new()

      assert result = MatchAllQuery.score(query, index, [])
      assert Enum.count(result) == 3

      for %{score: score} <- result do
        assert score == 1
      end
    end
  end

  describe "terms" do
    test "performs base functionality", %{index: index} do
      query =
        TermsQuery.new(
          field: :content,
          terms: ["fox"]
        )

      assert result = TermsQuery.score(query, index, [])
      assert Enum.count(result) == 1
      assert [%{ref: 1}] = result
    end

    test "boost", %{index: index} do
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

  describe "bool" do
    test "filters via must functionality", %{index: index} do
      query =
        BoolQuery.new(
          must: TermsQuery.new(field: :content, terms: ["lorem"]),
          should: [
            TermsQuery.new(field: :content, terms: ["dog"])
          ]
        )

      assert BoolQuery.score(query, index, []) |> Enum.count() == 1
    end

    test "filters via must_not functionality", %{index: index} do
      query =
        BoolQuery.new(
          must: TermsQuery.new(field: :content, terms: ["lorem"]),
          must_not: TermsQuery.new(field: :content, terms: ["ipsum"]),
          should: [
            TermsQuery.new(field: :content, terms: ["dog"])
          ]
        )

      refute BoolQuery.score(query, index, [])
             |> Enum.empty?()
    end
  end

  describe "match" do
    test "performs base functionality", %{index: index} do
      query = MatchQuery.new(field: :content, query: "brown fox")

      assert results = MatchQuery.score(query, index, [])
      assert Enum.count(results) == 1
      assert [%{ref: 1}] = results
    end

    test "honours minimum_should_match", %{index: index} do
      query = MatchQuery.new(field: :content, query: "brown fox quick", minimum_should_match: 2)

      assert results = MatchQuery.score(query, index, [])
      assert Enum.count(results) == 1
      assert [%{ref: 1}] = results
    end

    test "honours and operator", %{index: index} do
      query =
        MatchQuery.new(
          field: :content,
          query: "fox quick",
          operator: "and"
        )

      assert results = MatchQuery.score(query, index, [])
      assert Enum.count(results) == 1
      assert [%{ref: 1}] = results
    end
  end
end
