defmodule Elasticlunr.DocumentStoreTest do
  use ExUnit.Case

  alias Elasticlunr.DocumentStore

  describe "creating a new document store" do
    test "defaults save attribute to true" do
      assert %DocumentStore{documents: %{}, document_info: %{}, length: 0, save: true} =
               DocumentStore.new()
    end

    test "without saving documents" do
      assert %DocumentStore{documents: %{}, document_info: %{}, length: 0, save: false} =
               DocumentStore.new(false)
    end
  end

  describe "adding document to document store" do
    test "adds a new document and save document" do
      document = %{id: 10}
      document_store = DocumentStore.new()

      assert %DocumentStore{documents: %{10 => ^document}} =
               DocumentStore.add(document_store, 10, document)
    end

    test "saves document and update length" do
      document_store = DocumentStore.new()

      assert document_store = DocumentStore.add(document_store, 10, %{id: 10})
      assert %DocumentStore{length: 1} = document_store
      assert %DocumentStore{length: 2} = DocumentStore.add(document_store, 1, %{id: 1})
    end

    test "updates document data and does not update length" do
      document_store = DocumentStore.new()

      assert document_store = DocumentStore.add(document_store, 10, %{id: 10})
      assert %DocumentStore{length: 1, documents: %{10 => %{id: 10}}} = document_store

      assert %DocumentStore{length: 1, documents: %{10 => %{id: 1}}} =
               DocumentStore.add(document_store, 10, %{id: 1})
    end

    test "checks if document exists" do
      document_store = DocumentStore.new()

      assert document_store = DocumentStore.add(document_store, 10, %{id: 10})
      assert DocumentStore.exists?(document_store, 10)
      refute DocumentStore.exists?(document_store, 100)
    end
  end

  describe "retrieving document from document store" do
    test "returns document" do
      document = %{id: 10}

      document_store =
        DocumentStore.new()
        |> DocumentStore.add(10, document)

      assert ^document = DocumentStore.get(document_store, 10)
    end

    test "returns nil for non-existing document" do
      document_store = DocumentStore.new()

      assert is_nil(DocumentStore.get(document_store, 10))
    end

    test "returns nil for non-persitent store" do
      document = %{id: 10}

      document_store =
        DocumentStore.new(false)
        |> DocumentStore.add(10, document)

      refute DocumentStore.get(document_store, 10)
    end
  end

  describe "removing document from document store" do
    test "removes document" do
      document = %{id: 10}

      document_store =
        DocumentStore.new()
        |> DocumentStore.add(10, document)

      assert %DocumentStore{length: 1, documents: %{10 => %{id: 10}}} = document_store
      assert %DocumentStore{length: 0, documents: %{}} = DocumentStore.remove(document_store, 10)
    end
  end

  describe "adding field length of document field" do
    test "adds field length" do
      document = %{id: 10}

      document_store =
        DocumentStore.new()
        |> DocumentStore.add(10, document)

      assert %DocumentStore{
               length: 1,
               documents: %{10 => %{id: 10}},
               document_info: %{10 => %{name: 20}}
             } = DocumentStore.add_field_length(document_store, 10, :name, 20)
    end

    test "updates field length" do
      document = %{id: 10}

      document_store =
        DocumentStore.new()
        |> DocumentStore.add(10, document)

      assert %DocumentStore{document_info: %{10 => %{name: 20}}} =
               DocumentStore.add_field_length(document_store, 10, :name, 20)

      assert %DocumentStore{document_info: %{10 => %{name: 36}}} =
               DocumentStore.update_field_length(document_store, 10, :name, 36)
    end
  end

  describe "retrieving document field length" do
    test "returns nil" do
      document = %{id: 10}

      document_store =
        DocumentStore.new()
        |> DocumentStore.add(10, document)

      assert is_nil(DocumentStore.get_field_length(document_store, 10, :name))
    end

    test "returns field length" do
      document = %{id: 10}

      document_store =
        DocumentStore.new()
        |> DocumentStore.add(10, document)
        |> DocumentStore.add_field_length(10, :name, 20)

      assert 20 = DocumentStore.get_field_length(document_store, 10, :name)
    end
  end

  describe "reset document store" do
    test "clears store attributes" do
      document = %{id: 10}

      assert document_store =
               DocumentStore.new()
               |> DocumentStore.add(10, document)
               |> DocumentStore.add_field_length(10, :name, 20)

      assert %DocumentStore{} = document_store

      assert %DocumentStore{documents: %{}, document_info: %{}, length: 0, save: true} =
               DocumentStore.reset(document_store)
    end
  end
end
