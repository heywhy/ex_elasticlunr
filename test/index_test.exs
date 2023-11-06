defmodule Elasticlunr.IndexTest do
  use ExUnit.Case

  alias Box.Utils
  alias Elasticlunr.Book
  alias Faker.{Date, Lorem, Person}

  import Elasticlunr.Fixture

  setup_all do
    start_supervised!(Book)
    :ok
  end

  test "check if index is running" do
    assert Book.running?()
  end

  test "can save document" do
    document = %Book{
      views: 100,
      title: Lorem.word(),
      author: Person.name(),
      tags: ["fiction", "science"],
      release_date: Date.backward(1)
    }

    assert %Book{id: id, views: 100} = Book.save(document)
    assert is_binary(id)
  end

  test "can save multiple documents" do
    documents = [new_book(id: Utils.new_id()), new_book(id: Utils.new_id())]

    assert :ok = Book.save_all(documents)
    assert Enum.all?(documents, &match?(%{id: _id}, Book.get(&1.id)))
  end

  test "can retrieve document" do
    document = %Book{
      views: 100,
      title: Lorem.word(),
      author: Person.name(),
      tags: ["fiction", "science"],
      release_date: Date.backward(1)
    }

    assert document = Book.save(document)
    assert ^document = Book.get(document.id)
  end

  test "can remove document" do
    document = %Book{
      views: 100,
      title: Lorem.word(),
      author: Person.name(),
      tags: ["fiction", "science"],
      release_date: Date.backward(1)
    }

    assert %Book{id: id} = Book.save(document)
    assert :ok = Book.delete(id)
    refute Book.get(id)
  end
end
