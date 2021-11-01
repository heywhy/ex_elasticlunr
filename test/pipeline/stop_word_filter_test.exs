defmodule Elasticlunr.Pipeline.StopWordFilterTest do
  @moduledoc false
  use ExUnit.Case

  alias Elasticlunr.{Pipeline, Token}
  alias Elasticlunr.Pipeline.StopWordFilter

  describe "running stop_word_filter against tokens" do
    test "is a default runner for default pipeline" do
      assert Pipeline.default_runners()
             |> Enum.any?(fn
               StopWordFilter -> true
               _ -> false
             end)
    end

    test "removes stop words" do
      stop_words = ~w[the and but than when]

      assert [] =
               stop_words
               |> Enum.map(&Token.new/1)
               |> Enum.reject(&is_nil(StopWordFilter.call(&1, [])))
    end
  end
end
