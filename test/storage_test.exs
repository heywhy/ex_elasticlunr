defmodule Elasticlunr.StorageTest do
  use ExUnit.Case

  alias Elasticlunr.{Index, Storage}
  alias Elasticlunr.Storage.{Blackhole, Mock}

  import Mox

  setup :verify_on_exit!

  setup do
    Mox.stub_with(Mock, Blackhole)
    Application.put_env(:elasticlunr, :storage, Mock)

    on_exit(fn ->
      Application.delete_env(:elasticlunr, :storage)
    end)
  end

  test "preload/0" do
    index = Index.new()

    expect(Mock, :load_all, fn -> [index] end)

    assert [^index] = Storage.all()
  end

  test "write/1" do
    index = Index.new()

    expect(Mock, :write, 2, fn
      ^index -> :ok
      %{name: nil} -> {:error, "invalid index"}
    end)

    assert :ok = Storage.write(index)
    assert {:error, "invalid index"} = Storage.write(Index.new(name: nil))
  end

  test "read/1" do
    expect(Mock, :read, 2, fn
      "missing" -> {:error, "missing index"}
      name -> Index.new(name: name)
    end)

    assert {:error, "missing index"} = Storage.read("missing")
    assert %Index{name: "users"} = Storage.read("users")
  end

  test "delete/1" do
    expect(Mock, :delete, 2, fn
      "unknown-index" -> :error
      _ -> :ok
    end)

    assert :error = Storage.delete("unknown-index")
    assert :ok = Storage.delete("users")
  end
end
