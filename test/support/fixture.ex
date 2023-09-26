defmodule Elasticlunr.Fixture do
  alias Elasticlunr.Book
  alias Faker.{Commerce, Date, Lorem, Person}

  @spec new_book(keyword()) :: Book.t()
  def new_book(opts \\ []) do
    %Book{
      views: 100,
      id: opts[:id],
      title: Lorem.word(),
      author: Person.name(),
      price: Commerce.price(),
      tags: ["fiction", "science"],
      release_date: Date.backward(1)
    }
  end

  @spec tmp_dir!() :: Path.t()
  def tmp_dir! do
    dir =
      System.tmp_dir!()
      |> Path.join(FlakeId.get())

    :ok = File.mkdir!(dir)

    dir
  end

  @spec stemmer_fixture() :: map()
  def stemmer_fixture do
    with path <- Path.join([__DIR__, "fixture", "stemmer_fixture.json"]),
         {:ok, content} <- File.read(path),
         {:ok, map} <- Jason.decode(content) do
      map
    end
  end
end
