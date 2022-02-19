defmodule Elasticlunr.IndexManagerTest do
  use ExUnit.Case

  alias Elasticlunr.{Index, IndexManager}

  describe "working with index manager" do
    test "saves an index" do
      index = Index.new()

      assert {:ok, ^index} = IndexManager.save(index)
    end

    test "updates existing index" do
      index = Index.new()

      assert {:ok, ^index} = IndexManager.save(index)
      assert {:ok, ^index} = IndexManager.save(index)
    end

    test "removes an index" do
      index = Index.new()

      assert {:ok, ^index} = IndexManager.save(index)
      assert :ok = IndexManager.remove(index)
      assert :not_running = IndexManager.get(index.name)
    end

    test "fails to remove a non-existent index" do
      index = Index.new()

      assert :not_running = IndexManager.remove(index)
    end

    test "checks if an index is running" do
      index = Index.new()

      assert {:ok, _} = IndexManager.save(index)
      assert IndexManager.running?(index.name)
      refute IndexManager.running?("missing index")
    end
  end
end
