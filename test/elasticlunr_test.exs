defmodule ElasticlunrTest do
  use ExUnit.Case

  alias Elasticlunr.{Index, IndexManager}

  describe "creating index" do
    test "creates a new index" do
      assert %Index{name: "index_1", fields: %{}} = Elasticlunr.index("index_1")

      assert %Index{name: "index_2", fields: %{"title" => _, "body" => _}} =
               "index_2"
               |> Elasticlunr.index()
               |> Index.add_field("body")
               |> Index.add_field("title")
    end

    test "retrieves existing index instead of creating a new one" do
      index_name = Faker.Lorem.word()
      assert %Index{} = Elasticlunr.index(index_name)
      assert %Index{} = Elasticlunr.index(index_name)
      assert IndexManager.loaded?(index_name)
      assert %Index{name: ^index_name, fields: %{}} = Elasticlunr.index(index_name)
    end

    test "create a new index with default pipeline" do
      index_name = Faker.Lorem.word()
      default_pipline = Elasticlunr.default_pipeline()
      assert %Index{pipeline: ^default_pipline} = Elasticlunr.index(index_name)
    end
  end

  describe "updating index" do
    test "invokes callback function" do
      index_name = Faker.Lorem.word()

      callback = fn index ->
        send(self(), :callback_called)
        index
      end

      assert %Index{fields: %{}} = Elasticlunr.index(index_name)

      assert %Index{name: ^index_name} = Elasticlunr.update_index(index_name, callback)
      assert %Index{name: ^index_name} = IndexManager.get(index_name)

      assert_received :callback_called
    end

    test "updates index attributes" do
      index_name = Faker.Lorem.word()

      callback = fn index ->
        Index.add_field(index, "name")
      end

      assert %Index{fields: %{}} = Elasticlunr.index(index_name)

      assert %Index{name: ^index_name, fields: %{"name" => _}} =
               Elasticlunr.update_index(index_name, callback)

      assert %Index{name: ^index_name, fields: %{"name" => _}} = IndexManager.get(index_name)
    end
  end

  describe "serializing indexes" do
    test "writes to storage" do
      index_name = "serialized_index"

      documents =
        Stream.map(1..1_000, fn i ->
          %{
            "id" => i,
            "name" => Faker.Person.name(),
            "address" => Faker.Address.En.street_address(true)
          }
        end)

      callback = fn index ->
        documents = Enum.to_list(documents)

        index
        |> Index.add_field("name")
        |> Index.add_field("address")
        |> Index.add_documents(documents)
      end

      assert Elasticlunr.index(index_name)
      assert Elasticlunr.update_index(index_name, callback)
      assert :ok = Elasticlunr.flush_indexes()
    end
  end

  describe "unserializing indexes" do
    test "loads from storage" do
      assert :ok = Elasticlunr.load_indexes()
    end
  end
end
