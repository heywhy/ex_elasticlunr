defmodule Elasticlunr.IndexManagerTest do
  use ExUnit.Case

  alias Elasticlunr.{Index, IndexManager}

  describe "working with index manager" do
    test "saves an index" do
      index = Index.new()

      assert {:ok, ^index} = IndexManager.save(index)
    end

    test "fails when saving duplicate index" do
      index = Index.new()

      assert {:ok, ^index} = IndexManager.save(index)
      assert {:error, {:already_started, _}} = IndexManager.save(index)
    end

    test "updates existing index" do
      index = Index.new()

      assert {:ok, ^index} = IndexManager.save(index)
      assert ^index = IndexManager.update(index)
    end

    test "fails update action for non-existent index" do
      index = Index.new()

      assert :not_running = IndexManager.update(index)
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
  end
end
