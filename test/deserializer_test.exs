defmodule Elasticlunr.DeserializerTest do
  use ExUnit.Case

  alias Elasticlunr.{Deserializer, Field, Index}

  @tag :skip
  test "deserialize index" do
    data = [
      "settings#name:index|ref:id|pipeline:",
      "field#name:id|pipeline:Elixir.Elasticlunr.Index.IdPipeline|store_documents:false|store_positions:false",
      "documents#id|{}"
    ]

    index =
      to_stream(data)
      |> Deserializer.deserialize()

    assert %Index{name: "index"} = index
  end

  @tag :skip
  test "deserialize index with documents" do
    data = [
      "settings#name:index|ref:id|pipeline:",
      "field#name:body|pipeline:|store_documents:true|store_positions:true",
      "field#name:id|pipeline:Elixir.Elasticlunr.Index.IdPipeline|store_documents:false|store_positions:false",
      "documents#body|{\"1\":\"hello world\"}",
      "documents#id|{}",
      "token#field:body|{\"documents\":[1],\"idf\":0.6989700043360187,\"norm\":0.7071067811865475,\"term\":\"hello\",\"terms\":{\"1\":{\"positions\":[[0,5]],\"total\":1}},\"tf\":{\"1\":1.0}}",
      "token#field:body|{\"documents\":[1],\"idf\":0.6989700043360187,\"norm\":0.7071067811865475,\"term\":\"world\",\"terms\":{\"1\":{\"positions\":[[6,5]],\"total\":1}},\"tf\":{\"1\":1.0}}",
      "token#field:id|{\"documents\":[1],\"idf\":0.6989700043360187,\"norm\":1.0,\"term\":\"1\",\"terms\":{\"1\":{\"positions\":[[0,1]],\"total\":1}},\"tf\":{\"1\":1.0}}"
    ]

    index =
      to_stream(data)
      |> Deserializer.deserialize()

    assert ~w[body id] = Index.get_fields(index)
    assert field = Index.get_field(index, "body")
    assert Field.tokens(field) |> Enum.count() == 2
  end

  defp to_stream(data) do
    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(&Enum.at(data, &1))
    |> Stream.take(Enum.count(data))
  end
end
