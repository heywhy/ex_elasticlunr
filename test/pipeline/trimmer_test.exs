defmodule Elasticlunr.Pipeline.TimmerTest do
  @moduledoc false
  use ExUnit.Case

  alias Elasticlunr.{Pipeline, Token}
  alias Elasticlunr.Pipeline.Trimmer

  describe "running trimmer against tokens" do
    test "is a default runner for default pipeline" do
      assert Pipeline.default_runners()
             |> Enum.any?(fn
               Trimmer -> true
               _ -> false
             end)
    end

    test "passes through latin characters" do
      assert %Token{token: "hello"} = Token.new("hello")
    end

    test "removes leading and trailing punctuation" do
      assert %Token{token: "hello"} = Token.new("hello.") |> Trimmer.call()
      assert %Token{token: "it's"} = Token.new("it's") |> Trimmer.call()
      assert %Token{token: "james"} = Token.new("james'") |> Trimmer.call()
      assert %Token{token: "stop"} = Token.new("stop!'") |> Trimmer.call()
      assert %Token{token: "first"} = Token.new("first'") |> Trimmer.call()
      assert %Token{token: ""} = Token.new("") |> Trimmer.call()
      assert %Token{token: "tag"} = Token.new("[tag]") |> Trimmer.call()
      assert %Token{token: "tag"} = Token.new("[[[tag]]]") |> Trimmer.call()
      assert %Token{token: "hello"} = Token.new("[[!@#@!hello]]]}}}") |> Trimmer.call()
      assert %Token{token: "hello"} = Token.new("~!@@@hello***()()()]]") |> Trimmer.call()
    end
  end
end
