defmodule Elasticlunr.Fixture do
  alias Box.Utils
  alias Box.MemTable
  alias Box.SSTable
  alias Elasticlunr.Book
  alias Faker.{Commerce, Date, Lorem, Person, Pokemon}

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

  @spec new_sstable(Path.t()) :: Path.t()
  def new_sstable(dir, count \\ 10) do
    0
    |> Range.new(count - 1)
    |> Enum.reduce(MemTable.new(), fn _, mem_table ->
      MemTable.set(mem_table, Pokemon.name(), Pokemon.location(), Utils.now())
    end)
    |> SSTable.flush(dir)
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
