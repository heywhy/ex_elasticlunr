defmodule Elasticlunr.Fixture do
  alias Elasticlunr.Book
  alias Elasticlunr.FileMeta
  alias Elasticlunr.MemTable
  alias Elasticlunr.SSTable
  alias Elasticlunr.Utils
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

  @spec new_file_meta() :: FileMeta.t()
  def new_file_meta, do: %FileMeta{dir: tmp_dir!(), number: Utils.now()}

  @spec new_sstable(non_neg_integer()) :: FileMeta.t() | File.posix()
  def new_sstable(count \\ 10) do
    0
    |> Range.new(count - 1)
    |> Enum.reduce(MemTable.new(), fn _, mem_table ->
      MemTable.set(mem_table, Pokemon.name(), Pokemon.location(), Utils.now())
    end)
    |> SSTable.flush(new_file_meta())
    |> elem(1)
  end

  @spec tmp_dir!() :: Path.t()
  def tmp_dir! do
    dir =
      Utils.storage_dir()
      |> Path.join(Utils.new_id() |> Utils.id_to_string())

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
