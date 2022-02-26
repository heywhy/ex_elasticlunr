defmodule Elasticlunr.SerializerTest do
  use ExUnit.Case

  alias Elasticlunr.{Index, Serializer}

  test "serialize index without documents" do
    index = Index.new(name: "index")

    structure = [
      "settings#name:index|ref:id|pipeline:|on_conflict:index",
      "field#name:id|pipeline:Elixir.Elasticlunr.Index.IdPipeline|store_documents:false|store_positions:false",
      "documents#id|{}"
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
      "settings#name:index|ref:id|pipeline:|on_conflict:index",
      "field#name:body|pipeline:|store_documents:true|store_positions:true",
      "field#name:id|pipeline:Elixir.Elasticlunr.Index.IdPipeline|store_documents:false|store_positions:false",
      "documents#body|{\"1\":\"hello world\"}",
      "documents#id|{}",
      "token#field:body|{\"documents\":[1],\"idf\":0.6989700043360187,\"norm\":0.7071067811865475,\"term\":\"hello\",\"terms\":{\"1\":{\"positions\":[[0,5]],\"total\":1}},\"tf\":{\"1\":1.0}}",
      "token#field:body|{\"documents\":[1],\"idf\":0.6989700043360187,\"norm\":0.7071067811865475,\"term\":\"world\",\"terms\":{\"1\":{\"positions\":[[6,5]],\"total\":1}},\"tf\":{\"1\":1.0}}",
      "token#field:id|{\"documents\":[1],\"idf\":0.6989700043360187,\"norm\":1.0,\"term\":\"1\",\"terms\":{\"1\":{\"positions\":[[0,1]],\"total\":1}},\"tf\":{\"1\":1.0}}"
    ]

    data = Serializer.serialize(index) |> Enum.into([])

    assert structure == data
  end
end
