defmodule Elasticlunr.IndexTest do
  use ExUnit.Case

  alias Elasticlunr.Book
  alias Faker.{Date, Lorem, Person}

  setup_all do
    start_supervised!(Book)
    :ok
  end

  test "check if index is running" do
    assert Book.running?()
  end

  test "can save document" do
    document = %{
      views: 100,
      title: Lorem.word(),
      author: Person.name(),
      tags: ["fiction", "science"],
      release_date: Date.backward(1)
    }

    assert {:ok, %{id: id, views: 100}} = Book.save(document)
    assert is_binary(id)
  end

  test "can retrieve document" do
    document = %{
      views: 100,
      title: Lorem.word(),
      author: Person.name(),
      tags: ["fiction", "science"],
      release_date: Date.backward(1)
    }

    assert {:ok, %{id: id} = document} = Book.save(document)
    assert ^document = Book.get(id)
  end

  test "can remove document" do
    document = %{
      views: 100,
      title: Lorem.word(),
      author: Person.name(),
      tags: ["fiction", "science"],
      release_date: Date.backward(1)
    }

    assert {:ok, %{id: id}} = Book.save(document)
    assert :ok = Book.delete(id)
    refute Book.get(id)
  end
end
