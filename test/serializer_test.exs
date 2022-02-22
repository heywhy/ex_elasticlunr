defmodule Elasticlunr.SerializerTest do
  use ExUnit.Case

  alias Elasticlunr.{Index, Serializer}

  test "serialize index without documents" do
    index = Index.new(name: "index")

    structure = [
      "settings#name:index|ref:id|pipeline:",
      "db#name:elasticlunr_index|options:compressed,named_table,set,public",
      "field#name:id|pipeline:Elixir.Elasticlunr.Index.IdPipeline|store_documents:false|store_positions:false"
    ]

    data = Serializer.serialize(index) |> Enum.into([])

    assert structure == data
  end

  test "serialize index with documents" do
    index =
      Index.new(name: "index")
      |> Index.add_field("body")
      |> Index.add_documents([%{"id" => 1, "body" => "hello world"}])

    structure = [
      "settings#name:index|ref:id|pipeline:",
      "db#name:elasticlunr_index|options:compressed,named_table,set,public",
      "field#name:body|pipeline:|store_documents:true|store_positions:true",
      "field#name:id|pipeline:Elixir.Elasticlunr.Index.IdPipeline|store_documents:false|store_positions:false"
    ]

    data = Serializer.serialize(index) |> Enum.into([])

    assert structure == data
  end
end
