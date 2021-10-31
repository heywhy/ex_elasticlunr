defmodule ElasticlunrTest do
  use ExUnit.Case

  alias Elasticlunr.{Index, IndexManager}

  describe "creating index" do
    test "creates a new index" do
      assert %Index{name: "index_1", fields: []} = Elasticlunr.index("index_1")

      assert %Index{name: "index_2", fields: ~w[title body]a} =
               Elasticlunr.index("index_2", fields: ~w[title body]a)
    end

    test "retrieves existing index instead of creating a new one" do
      index_name = Faker.Lorem.word()
      assert %Index{} = Elasticlunr.index(index_name)
      assert %Index{} = Elasticlunr.index(index_name)
      assert IndexManager.loaded?(index_name)
      assert %Index{name: ^index_name, fields: []} = Elasticlunr.index(index_name)
    end
  end
end
