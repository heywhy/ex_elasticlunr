defmodule Elasticlunr.DeserializerTest do
  use ExUnit.Case

  alias Elasticlunr.{Deserializer, Index}

  test "deserialize index" do
    data = [
      "settings#name:index|ref:id|pipeline:|on_conflict:index",
      "db#name:elasticlunr_index|options:compressed,named_table,set,public",
      "field#name:id|pipeline:Elixir.Elasticlunr.Index.IdPipeline|store_documents:false|store_positions:false"
    ]

    index =
      to_stream(data)
      |> Deserializer.deserialize()

    assert %Index{name: "index"} = index
  end

  defp to_stream(data) do
    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(&Enum.at(data, &1))
    |> Stream.take(Enum.count(data))
  end
end
