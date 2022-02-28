defmodule Elasticlunr.IndexTest do
  use ExUnit.Case

  alias Elasticlunr.{Field, Index, Pipeline, Token}
  alias Faker.Address.En, as: Address

  describe "creating an index" do
    test "creates a new instance" do
      assert %Index{name: name} = Index.new()
      assert is_binary(name)
      assert %Index{name: :test_index, ref: "id", fields: %{}} = Index.new(name: :test_index)

      assert %Index{name: :test_index, ref: "name", fields: %{}} =
               Index.new(name: :test_index, ref: "name")
    end

    test "creates a new instance and populate fields" do
      assert %Index{fields: %{"id" => %Field{}, "name" => %Field{}}} =
               Index.add_field(Index.new(), "name")
    end
  end

  describe "modifying an index" do
    test "adds new fields" do
      index = Index.new()
      assert %Index{fields: %{}} = index
      assert index = Index.add_field(index, "name")
      assert %Index{fields: %{"name" => %Field{}}} = index

      assert %Index{fields: %{"name" => %Field{}, "bio" => %Field{}}} =
               Index.add_field(index, "bio")
    end

    test "save document" do
      index = Index.add_field(Index.new(), "name")

      assert %Index{fields: %{"name" => %Field{store: true}}} = index
      assert %Index{fields: %{"name" => %Field{store: false}}} = Index.save_document(index, false)
    end

    test "updates a field" do
      index = Index.new()
      assert %Index{fields: %{}} = index
      assert index = Index.add_field(index, "name")
      assert field = Index.get_field(index, "name")
      assert %Field{query_pipeline: nil} = field

      pipeline = Pipeline.new()

      assert %Field{query_pipeline: ^pipeline} =
               index
               |> Index.update_field("name", %{field | query_pipeline: pipeline})
               |> Index.get_field("name")
    end

    test "fails to update missing field" do
      index = Index.new()
      assert %Index{fields: %{}} = index

      assert_raise RuntimeError, "Unknown field address in index", fn ->
        Index.update_field(index, "address", Field.new([]))
      end
    end
  end

  describe "fiddling with an index" do
    test "adds document" do
      index =
        Index.new()
        |> Index.add_field("bio")

      assert index =
               Index.add_documents(index, [
                 %{
                   "id" => 10,
                   "bio" => Faker.Lorem.paragraph()
                 }
               ])

      assert Index.documents_size(index) == 1

      assert index
             |> Index.add_documents([
               %{
                 "id" => 29,
                 "bio" => Faker.Lorem.paragraph()
               }
             ])
             |> Index.documents_size()
             |> Kernel.==(2)
    end

    @tag :skip
    test "adds documents and flatten nested attributes" do
      index =
        Index.new()
        |> Index.add_field("name")
        |> Index.add_field("address")

      document = %{
        "id" => 20,
        "name" => "nelson",
        "address" => %{
          "city" => Address.city(),
          "country" => Address.country_code(),
          "line1" => Address.street_address(),
          "line2" => Address.secondary_address(),
          "state" => Address.state()
        }
      }

      index = Index.add_documents(index, [document])

      query = %{
        "bool" => %{
          "should" => %{
            "match" => %{"address.city" => get_in(document, ~w[address city])}
          }
        }
      }

      assert %Index{fields: %{"address.city" => %Field{}}} = index
      assert Index.documents_size(index) == 1
      refute Index.search(index, %{"query" => query}) |> Enum.empty?()
    end

    @tag :skip
    test "removes documents with nested attributes" do
      index =
        Index.new()
        |> Index.add_field("name")
        |> Index.add_field("address")

      document = %{
        "id" => 20,
        "name" => "nelson",
        "address" => %{
          "city" => Address.city(),
          "country" => Address.country_code(),
          "line1" => Address.street_address(),
          "line2" => Address.secondary_address(),
          "state" => Address.state()
        }
      }

      index = Index.add_documents(index, [document])

      assert %Index{fields: %{"address.city" => %Field{}}} = index
      assert Index.documents_size(index) == 1

      assert index = Index.remove_documents(index, [20])
      assert %Index{fields: %{"address.city" => %Field{}}} = index
      assert Index.documents_size(index) == 0
    end

    test "allows addition of document with empty field" do
      index =
        Index.new()
        |> Index.add_field("bio")
        |> Index.add_field("title")

      assert index = Index.add_documents(index, [%{"id" => 10, "bio" => "", "title" => "test"}])

      assert term_frequency =
               index
               |> Index.get_field("title")
               |> Field.term_frequency("test")

      assert index
             |> Index.get_field("title")
             |> Field.length(:tf, "test")
             |> Kernel.==(1)

      assert term_frequency
             |> Enum.find(&(elem(&1, 0) == 10))
             |> Kernel.==({10, 1})
    end

    @tag :skip
    test "fails when adding duplicate document" do
      index = Index.add_field(Index.new(), "bio")

      document = %{
        "id" => 10,
        "bio" => Faker.Lorem.paragraph()
      }

      assert index = Index.add_documents(index, [document])

      assert_raise RuntimeError, "Document id 10 already exists in the index", fn ->
        Index.add_documents(index, [document])
      end
    end

    test "removes document" do
      index =
        Index.new()
        |> Index.add_field("id")
        |> Index.add_field("bio")

      document = %{
        "id" => 10,
        "bio" => "this is a test"
      }

      document_2 = %{
        "id" => 30,
        "bio" => "this is another test"
      }

      assert index = Index.add_documents(index, [document_2, document])
      assert Index.documents_size(index) == 2
      assert index = Index.remove_documents(index, [10])
      assert Index.documents_size(index) == 1
      assert field = Index.get_field(index, "bio")
      refute Field.has_token(field, "a")
      assert Field.has_token(field, "another")
      assert is_nil(Field.get_token(field, "a"))
      assert %{idf: idf} = Field.get_token(field, "another")
      assert idf > 0
      %{documents: documents} = Field.get_token(field, "another")
      assert [30] = Enum.to_list(documents)
    end

    test "does not remove unknown document" do
      index = Index.add_field(Index.new(), "bio")

      document = %{
        "id" => 10,
        "bio" => Faker.Lorem.paragraph()
      }

      assert index = Index.add_documents(index, [document])
      assert Index.documents_size(index) == 1
      assert index = Index.remove_documents(index, [11])
      assert Index.documents_size(index) == 1
    end

    test "update existing document" do
      index = Index.add_field(Index.new(), "bio")

      document = %{
        "id" => 10,
        "bio" => Faker.Lorem.paragraph()
      }

      index = Index.add_documents(index, [document])

      assert Index.documents_size(index) == 1
      updated_document = %{document | "bio" => Faker.Lorem.paragraph()}
      assert index = Index.update_documents(index, [updated_document])
      assert Index.documents_size(index) == 1
    end

    test "search for a document" do
      index = Index.add_field(Index.new(), "bio")

      document = %{
        "id" => 10,
        "bio" => "foo"
      }

      index = Index.add_documents(index, [document])

      assert Index.search(index, "foo") |> Enum.count() == 1
      updated_document = %{document | "bio" => "bar"}
      index = Index.update_documents(index, [updated_document])
      assert Index.search(index, "bar") |> Enum.count() == 1
      assert Index.search(index, "foo") |> Enum.empty?()
    end

    test "allows the use of multiple, different pipelines for searching and indexing" do
      index = Index.add_field(Index.new(), "info")

      callback = fn %Token{token: token} ->
        tokens = [token]

        case token == "foo" do
          false ->
            tokens

          true ->
            ~w[bar baz barry] ++ tokens
        end
      end

      query_pipeline = Pipeline.new([callback])

      field =
        index
        |> Index.get_field("info")
        |> Field.set_query_pipeline(query_pipeline)

      index = Index.update_field(index, "info", field)

      index =
        index
        |> Index.add_documents([
          %{"id" => "a", "info" => "Barry had a beer with Fred in the bar"},
          %{"id" => "b", "info" => "the bar is empty"}
        ])

      results =
        Index.search(index, %{
          "query" => %{
            "match" => %{"info" => "foo"}
          }
        })

      assert Enum.count(results) == 2
      assert [%{score: score_1}, %{score: score_2}] = results
      assert score_2 < score_1

      results =
        Index.search(index, %{
          "query" => %{
            "match" => %{"info" => "fred"}
          }
        })

      assert Enum.count(results) == 1
    end
  end
end
