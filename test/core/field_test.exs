defmodule Elasticlunr.FieldTest do
  use ExUnit.Case

  alias Elasticlunr.Core.Field
  alias Elasticlunr.{DB, Pipeline, Token}

  setup context do
    opts = [
      pipeline: Pipeline.new(),
      db: DB.init(:field_test, ~w[public]a)
    ]

    field =
      Field.new(opts)
      |> Field.add([%{id: 1, content: "hello world"}])

    :ok = on_exit(fn -> true = DB.destroy(field.db) end)

    Map.put(context, :field, field)
  end

  test "tokens/1", %{field: field} do
    tokens = Field.tokens(field)

    assert %Stream{} = tokens
    refute Enum.empty?(tokens)
    assert [%{tf: 1, documents: documents} | _] = Enum.to_list(tokens)
    assert [1] = Enum.to_list(documents)
  end

  test "documents/1", %{field: field} do
    assert documents = Field.documents(field)
    assert [1] = Enum.to_list(documents)
  end

  test "term_frequency/2", %{field: field} do
    assert tf = Field.term_frequency(field, "hello")
    assert [{1, 1.0}] = Enum.to_list(tf)
    refute Field.term_frequency(field, "missing")
  end

  test "has_token/2", %{field: field} do
    assert Field.has_token(field, "hello")
    refute Field.has_token(field, "missing")
  end

  test "get_token/2", %{field: field} do
    assert %{term: "hello", tf: 1} = Field.get_token(field, "hello")
    refute Field.get_token(field, "missing")
  end

  test "set_query_pipeline/2", %{field: field} do
    pipeline = Pipeline.new()
    assert %Field{query_pipeline: nil} = field
    assert %Field{query_pipeline: ^pipeline} = Field.set_query_pipeline(field, pipeline)
  end

  test "add/2", %{field: field} do
    assert Enum.count(Field.documents(field)) == 1
    assert field = Field.add(field, [%{id: 10, content: "testing"}])
    assert Enum.count(Field.documents(field)) == 2
    assert Field.has_token(field, "testing")
  end

  test "length/2", %{field: field} do
    assert Field.length(field, :ids) == 1
    assert Field.length(field, :idf, "hello") == 1
    assert Field.length(field, :term, "world") == 1
    assert Field.length(field, :tf, "world") == 1
  end

  test "update/2", %{field: field} do
    assert field = Field.update(field, [%{id: 1, content: "worse"}])
    assert Field.has_token(field, "worse")
    assert Enum.count(Field.documents(field)) == 1
  end

  test "remove/2", %{field: field} do
    assert field = Field.remove(field, [1])
    refute Field.has_token(field, "worse")
    assert Enum.empty?(Field.documents(field))
  end

  test "analyze/3", %{field: field} do
    assert [%Token{token: "coming"}] = Field.analyze(field, "coming", [])
    assert [%Token{token: "coming"}] = Field.analyze(field, "coming", is_query: true)

    assert [%Token{token: "foo"}] =
             field
             |> Field.set_query_pipeline(Pipeline.new([fn _ -> Token.new("foo") end]))
             |> Field.analyze("coming", is_query: true)
  end

  test "terms/3", %{field: field} do
    assert %{1 => _} = Field.terms(field, terms: ["hello"])
    assert %{1 => _} = Field.terms(field, terms: [~r/hello/])
    assert %{1 => _} = Field.terms(field, terms: ["hello"], fuzziness: 2)
    assert Enum.empty?(Field.terms(field, terms: ["missing"]))
  end
end
