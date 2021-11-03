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

  describe "fiddling with an index" do
    test "adds document", %{pipeline: pipeline} do
      index = Index.new(:test_index, pipeline, fields: ~w[id bio]a)

      assert index =
               Index.add_documents(index, [
                 %{
                   id: 10,
                   bio: Faker.Lorem.paragraph()
                 }
               ])

      assert %Index{documents_size: 1} = index

      assert %Index{documents_size: 2} =
               Index.add_documents(index, [
                 %{
                   id: 29,
                   bio: Faker.Lorem.paragraph()
                 }
               ])
    end

    test "fails when adding duplicate document", %{pipeline: pipeline} do
      index = Index.new(:test_index, pipeline, fields: ~w[id bio]a)

      document = %{
        id: 10,
        bio: Faker.Lorem.paragraph()
      }

      assert index = Index.add_documents(index, [document])

      assert_raise RuntimeError, "Document id 10 already exists in the index", fn ->
        Index.add_documents(index, [document])
      end
    end

    test "removes document", %{pipeline: pipeline} do
      index = Index.new(:test_index, pipeline, fields: ~w[id bio]a)

      document = %{
        id: 10,
        bio: Faker.Lorem.paragraph()
      }

      assert index = Index.add_documents(index, [document])
      assert %Index{documents_size: 1} = index
      assert %Index{documents_size: 0} = Index.remove_documents(index, [10])
    end

    test "does not remove unknown document", %{pipeline: pipeline} do
      index = Index.new(:test_index, pipeline, fields: ~w[id bio]a)

      document = %{
        id: 10,
        bio: Faker.Lorem.paragraph()
      }

      assert index = Index.add_documents(index, [document])
      assert %Index{documents_size: 1} = index
      assert %Index{documents_size: 1} = Index.remove_documents(index, [11])
    end

    test "update existing document", %{pipeline: pipeline} do
      index = Index.new(:test_index, pipeline, fields: ~w[id bio]a)

      document = %{
        id: 10,
        bio: Faker.Lorem.paragraph()
      }

      index = Index.add_documents(index, [document])

      assert %Index{documents_size: 1} = index
      updated_document = %{document | bio: Faker.Lorem.paragraph()}
      assert %Index{documents_size: 1} = Index.update_documents(index, [updated_document])
    end

    test "search for a document", %{pipeline: pipeline} do
      index = Index.new(:test_index, pipeline, fields: ~w[bio]a)

      document = %{
        id: 10,
        bio: "foo"
      }

      index = Index.add_documents(index, [document])

      assert Index.search(index, "foo") |> Enum.count() == 1
      updated_document = %{document | bio: "bar"}
      index = Index.update_documents(index, [updated_document])
      assert Index.search(index, "bar") |> Enum.count() == 1
      assert Index.search(index, "foo") |> Enum.empty?()
    end
  end
end
