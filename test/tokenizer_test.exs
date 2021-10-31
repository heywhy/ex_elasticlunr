defmodule Elasticlunr.TokenizerTest do
  use ExUnit.Case

  alias Elasticlunr.{Token, Tokenizer}

  describe "tokenizing string" do
    test "splits to list of tokens" do
      str = "the man came home"

      tokenized_str = [
        Token.new("the", %{start: 0, end: 2}),
        Token.new("man", %{start: 4, end: 6}),
        Token.new("came", %{start: 8, end: 11}),
        Token.new("home", %{start: 13, end: 16})
      ]

      assert ^tokenized_str = Tokenizer.tokenize(str)
    end

    test "downcase tokens" do
      assert ~w[foo bar] =
               Tokenizer.tokenize("FOO BAR")
               |> Enum.map(& &1.token)
    end

    test "removes whitespace and hyphens" do
      assert ~w[foo bar] =
               Tokenizer.tokenize("  FOO    BAR   ")
               |> Enum.map(& &1.token)

      assert ~w[take the new york san francisco flight] =
               Tokenizer.tokenize("take the New York-San Francisco flight")
               |> Enum.map(& &1.token)

      assert ~w[solve for a b] =
               Tokenizer.tokenize("Solve for A - B")
               |> Enum.map(& &1.token)
    end

    test "with custom separator" do
      assert ~w[hello world i love] =
               Tokenizer.tokenize("hello/world/I/love", ~r/\/+/)
               |> Enum.map(& &1.token)

      assert ~w[hello world i love] =
               Tokenizer.tokenize("hello\\world\\I\\love", ~r/[\\]+/)
               |> Enum.map(& &1.token)

      assert ~w[hello world apple pie] =
               Tokenizer.tokenize("hello/world/%%%apple%pie", ~r/[\/\%]+/)
               |> Enum.map(& &1.token)
    end
  end
end
