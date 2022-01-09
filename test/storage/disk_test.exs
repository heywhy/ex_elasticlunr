defmodule Elasticlunr.Storage.DiskTest do
  use ExUnit.Case

  alias Elasticlunr.Index
  alias Elasticlunr.Pipeline
  alias Elasticlunr.Storage.Disk

  @otp_app :elasticlunr

  setup do
    storage_path = Path.join(__DIR__, "../../storage")

    Application.put_env(@otp_app, Disk, directory: storage_path)

    on_exit(fn ->
      Disk.files()
      |> Enum.each(&Disk.delete/1)

      Application.delete_env(@otp_app, Disk)
    end)
  end

  defp fixture_storage(_context) do
    opts = Application.get_env(@otp_app, Disk)
    storage_path = Path.join(__DIR__, "../support/fixture")
    Application.put_env(@otp_app, Disk, directory: storage_path)

    on_exit(fn ->
      Application.put_env(@otp_app, Disk, opts)
    end)
  end

  describe "serializing an index" do
    test "writes to disk" do
      index = Index.new()
      options = Application.get_env(@otp_app, Disk)
      file = Path.join(options[:directory], "#{index.name}.index")

      assert :ok = Disk.write(index)
      assert File.exists?(file)
      assert {:ok, %File.Stat{size: size}} = File.stat(file)
      assert size > 0
    end
  end

  describe "unserializing an index" do
    test "reads from disk" do
      pipeline = Pipeline.new(Pipeline.default_runners())

      document = %{
        "id" => Faker.UUID.v4(),
        "last_name" => Faker.Person.last_name(),
        "first_name" => Faker.Person.first_name()
      }

      index =
        Index.new(pipeline: pipeline)
        |> Index.add_field("first_name")
        |> Index.add_field("last_name")
        |> Index.add_documents([document])

      :ok = Disk.write(index)

      assert index == Disk.read(index.name)
    end
  end

  describe "getting all serialized indexes" do
    setup [:fixture_storage]

    test "loads and deserialize indexes" do
      assert [%Index{name: "users"} = index] =
               Disk.load_all()
               |> Enum.to_list()

      assert [_] = Index.search(index, "rose")
    end
  end

  describe "deleting index from storage" do
    test "works successfully" do
      index = Index.new()
      options = Application.get_env(@otp_app, Disk)
      file = Path.join(options[:directory], "#{index.name}.index")

      :ok = Disk.write(index)
      assert :ok = Disk.delete(index.name)
      refute File.exists?(file)
    end

    test "fails for missing index" do
      assert {:error, :enoent} = Disk.delete("missing")
    end
  end
end
