defmodule Elasticlunr.WalTest do
  use ExUnit.Case, async: true

  alias Elasticlunr.MemTable
  alias Elasticlunr.MemTable.Entry
  alias Elasticlunr.Utils
  alias Elasticlunr.Wal

  setup do
    dir = System.tmp_dir!() |> Path.join(Utils.new_id() |> Utils.id_to_string())

    :ok = File.mkdir!(dir)

    on_exit(fn -> File.rm_rf!(dir) end)

    [dir: dir]
  end

  test "create/1", %{dir: dir} do
    assert %Wal{fd: fd} = Wal.create(dir)
    assert is_pid(fd)
  end

  test "close/1", %{dir: dir} do
    wal = Wal.create(dir)

    assert :ok = Wal.close(wal)
  end

  test "from_path/1", %{dir: dir} do
    wal = Wal.create(dir)
    :ok = Wal.close(wal)

    assert [file] = Wal.list(dir)
    assert %Wal{fd: fd} = Wal.from_path(file)
    assert is_pid(fd)
  end

  test "set/4", %{dir: dir} do
    wal = Wal.create(dir)

    assert {:ok, ^wal} = Wal.set(wal, "key", "value", 1)
    assert_raise ArgumentError, fn -> Wal.set(wal, :atom, %{}, 1) end
  end

  test "remove/3", %{dir: dir} do
    wal = Wal.create(dir)

    assert {:ok, ^wal} = Wal.remove(wal, "key", 1)
    assert_raise ArgumentError, fn -> Wal.remove(wal, :atom, 1) end
  end

  test "delete/1", %{dir: dir} do
    {:ok, wal} = Wal.create(dir) |> Wal.set("key", "value", 1)

    assert [_] = Wal.list(dir)
    assert :ok = Wal.delete(wal)
    assert [] = Wal.list(dir)
  end

  test "load_from_dir/1", %{dir: dir} do
    {:ok, _wal} =
      Wal.create(dir)
      |> Wal.set("key", "value", 1)
      |> then(&elem(&1, 1))
      |> Wal.set("key1", "value1", 2)

    assert {%Wal{}, %MemTable{} = mem_table} = Wal.load_from_dir(dir)
    assert %Entry{value: "value"} = MemTable.get(mem_table, "key")
    assert %Entry{value: "value1"} = MemTable.get(mem_table, "key1")
  end
end
