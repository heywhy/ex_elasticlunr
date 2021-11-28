defmodule Elasticlunr.DiskStorageTest do
  use ExUnit.Case

  alias Elasticlunr.Index
  alias Elasticlunr.Storage.Disk
  alias Elasticlunr.Test.Fixture

  import Fixture

  describe "serializing an index" do
    test "writes to disk" do
      index = Index.new()
      options = Application.get_env(:elasticlunr, Disk)

      assert :ok = Disk.write(index)
      assert file = Path.join(options[:directory], "#{index.name}.index")
      assert File.exists?(file)
      assert {:ok, %File.Stat{size: size}} = File.stat(file)
      assert size > 0
    end
  end

  describe "unserializing an index" do
    test "reads from disk" do
      opts = [pipeline: Elasticlunr.default_pipeline()]

      document = %{
        "id" => Faker.UUID.v4(),
        "last_name" => Faker.Person.last_name(),
        "first_name" => Faker.Person.first_name()
      }

      index =
        Index.new(opts)
        |> Index.add_field("first_name")
        |> Index.add_field("last_name")
        |> Index.add_documents([document])

      :ok = Disk.write(index)

      assert index == Disk.read(index.name)
    end
  end

  describe "getting all serialized indexes" do
    test "loads and desirialize indexes" do
      assert [%Index{name: "users"}] =
               Disk.load_all(directory: disk_storage_path())
               |> Enum.to_list()
    end
  end
end
