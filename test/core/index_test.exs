defmodule Elasticlunr.IndexTest do
  use ExUnit.Case

  alias Elasticlunr.{Field, Index}

  setup context do
    Map.put(context, :pipeline, Elasticlunr.default_pipeline())
  end

  describe "creating an index" do
    test "creates a new instance", %{pipeline: pipeline} do
      assert %Index{name: :test_index, ref: :id, fields: %{}} = Index.new(:test_index, pipeline)

      assert %Index{name: :test_index, ref: :name, fields: %{}} =
               Index.new(:test_index, pipeline, ref: :name)
    end

    test "creates a new instance and populate fields", %{pipeline: pipeline} do
      fields = ~w[id name]a

      assert %Index{name: :test_index, fields: %{id: %Field{}, name: %Field{}}} =
               Index.new(:test_index, pipeline, fields: fields)
    end
  end

  describe "modifying an index" do
    test "adds new fields", %{pipeline: pipeline} do
      index = Index.new(:test_index, pipeline)
      assert %Index{fields: %{}} = index
      assert index = Index.add_field(index, :name)
      assert %Index{fields: %{name: %Field{}}} = index
      assert %Index{fields: %{name: %Field{}, bio: %Field{}}} = Index.add_field(index, :bio)
    end

    test "save document", %{pipeline: pipeline} do
      index =
        :test_index
        |> Index.new(pipeline)
        |> Index.add_field(:name)

      assert %Index{fields: %{name: %Field{store: true}}} = index
      assert %Index{fields: %{name: %Field{store: false}}} = Index.save_document(index, false)
    end
  end
end
