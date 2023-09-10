defmodule Elasticlunr.MemTableTest do
  use ExUnit.Case, async: true

  alias Box.MemTable
  alias Box.MemTable.Entry

  describe "setting a key" do
    test "adds a new entry" do
      mem_table =
        MemTable.new()
        |> MemTable.set("key", "value", 1)
        |> MemTable.set("key1", "value1", 2)

      assert 2 = MemTable.length(mem_table)
    end

    test "updates existing entry" do
      mem_table =
        MemTable.new()
        |> MemTable.set("key", "value", 1)
        |> MemTable.set("key", "value1", 2)

      assert 1 = MemTable.length(mem_table)
      assert %Entry{key: "key", value: "value1"} = MemTable.get(mem_table, "key")
    end
  end

  describe "removing a key" do
    test "sets entry to deleted" do
      mem_table =
        MemTable.new()
        |> MemTable.set("key", "value", 1)
        |> MemTable.set("key1", "value1", 2)
        |> MemTable.remove("key", 3)

      assert 2 = MemTable.length(mem_table)
      assert %Entry{key: "key", deleted: true, value: nil} = MemTable.get(mem_table, "key")
    end

    test "adds a deletion entry for non-existing key" do
      mem_table = MemTable.remove(MemTable.new(), "key", 3)

      assert 1 = MemTable.length(mem_table)
      assert %Entry{key: "key", deleted: true} = MemTable.get(mem_table, "key")
    end
  end

  describe "" do
    setup do
      mem_table =
        MemTable.new()
        |> MemTable.set("key", "value", 1)
        |> MemTable.set("key1", "value1", 2)
        |> MemTable.remove("key", 3)
        |> MemTable.set("key2", "value2", 4)

      dir = System.tmp_dir!() |> Path.join(FlakeId.get())

      :ok = File.mkdir!(dir)

      on_exit(fn -> File.rm_rf!(dir) end)

      [dir: dir, mem_table: mem_table]
    end

    test "writes entries to file", %{dir: dir, mem_table: mem_table} do
      assert :ok = MemTable.flush(mem_table, dir)
      assert [file] = MemTable.list(dir)
      assert %File.Stat{size: size} = File.stat!(file)
      assert size > 0
    end

    test "rebuild memtable from file", %{dir: dir, mem_table: mem_table} do
      :ok = MemTable.flush(mem_table, dir)

      [file] = MemTable.list(dir)

      assert new_mem_table = MemTable.from_file(file)
      assert new_mem_table == mem_table
    end

    test "retrieve key", %{mem_table: mem_table} do
      refute MemTable.get(mem_table, "unknown")
      assert %Entry{key: "key2", value: "value2"} = MemTable.get(mem_table, "key2")
    end

    test "retrieve through the existing segments", %{dir: dir, mem_table: mem_table} do
      :ok = MemTable.flush(mem_table, dir)

      mem_table =
        MemTable.new()
        |> MemTable.set("name", "elasticlunr", 5)
        |> MemTable.set("key", "new_value", 6)

      assert %Entry{} = MemTable.get(mem_table, "name", dir)
      assert %Entry{value: "new_value"} = MemTable.get(mem_table, "key", dir)
      assert %Entry{value: "value2"} = MemTable.get(mem_table, "key2", dir)
    end
  end
end
