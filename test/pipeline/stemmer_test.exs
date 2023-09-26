defmodule Elasticlunr.Pipeline.StemmerTest do
  use ExUnit.Case

  alias Elasticlunr.Token
  alias Elasticlunr.{Pipeline, Pipeline.Stemmer}

  import Elasticlunr.Fixture

  describe "running stemmer against tokens" do
    test "works as expected" do
      stemmer_fixture()
      |> Enum.each(fn {word, stemmed_word} ->
        token = Token.new(word)
        assert Stemmer.call(token) == Token.new(stemmed_word)
      end)
    end

    test "is a default runner for default pipeline" do
      assert Pipeline.default_runners()
             |> Enum.any?(fn
               Stemmer -> true
               _ -> false
             end)
    end
  end
end
