defmodule Elasticlunr.SSTableTest do
  use ExUnit.Case, async: true

  alias Elasticlunr.FileMeta
  alias Elasticlunr.MemTable
  alias Elasticlunr.SSTable
  alias Elasticlunr.SSTable.Entry
  alias Elasticlunr.Utils

  import Elasticlunr.Fixture

  setup do
    file = new_file_meta()

    mem_table =
      MemTable.new()
      |> MemTable.set("key", "value", 1)
      |> MemTable.set("key1", "value1", 2)

    on_exit(fn -> File.rm_rf(file.dir) end)

    [dir: file.dir, file_meta: file, mem_table: mem_table]
  end

  test "count/1", %{file_meta: file_meta, mem_table: mem_table} do
    ss_table = flush(mem_table, file_meta)

    assert SSTable.count(ss_table) == 2
  end

  test "contains?/2", %{file_meta: file_meta, mem_table: mem_table} do
    ss_table = flush(mem_table, file_meta)

    assert SSTable.contains?(ss_table, "key")
    assert SSTable.contains?(ss_table, "key1")
    refute SSTable.contains?(ss_table, "unknown")
  end

  test "get!/2", %{file_meta: file_meta, mem_table: mem_table} do
    ss_table = flush(mem_table, file_meta)

    assert %Entry{key: "key"} = SSTable.get!(ss_table, "key")
    assert %Entry{key: "key1"} = SSTable.get!(ss_table, "key1")
    refute SSTable.get!(ss_table, "unknown")
  end

  test "flush/2", %{file_meta: file_meta, mem_table: mem_table} do
    assert {:ok, %FileMeta{size: size}} = SSTable.flush(mem_table, file_meta)
    assert size > 0
  end

  test "from_path/1", %{file_meta: file_meta, mem_table: mem_table} do
    mem_table = MemTable.remove(mem_table, "key", 3)

    assert {:ok, file_meta} = SSTable.flush(mem_table, file_meta)
    assert {:ok, ss_table} = SSTable.from_path(file_meta)
    assert %Entry{key: "key", deleted: true} = SSTable.get!(ss_table, "key")
  end

  test "merge/1", %{dir: dir, file_meta: file_meta} do
    elapsed_tombstone_ts =
      DateTime.utc_now()
      |> DateTime.add(-10, :day)
      |> DateTime.to_unix(:microsecond)

    mem_table1 =
      MemTable.new()
      |> MemTable.set("handbag", "8786", Utils.now())
      |> MemTable.set("handful", "40308", Utils.now())
      |> MemTable.set("handicap", "65995", Utils.now())
      |> MemTable.set("handkerchief", "16324", Utils.now())

    mem_table2 =
      MemTable.new()
      |> MemTable.set("handcuffs", "2729", Utils.now())
      |> MemTable.set("handful", "42307", Utils.now())
      |> MemTable.set("handicap", "67884", Utils.now())
      |> MemTable.set("handkerchief", "20952", Utils.now())

    mem_table3 =
      MemTable.new()
      |> MemTable.set("handful", "44662", Utils.now())
      |> MemTable.set("handicap", "70836", Utils.now())
      |> MemTable.set("handiwork", "45521", Utils.now())
      |> MemTable.remove("handkerchief", Utils.now())
      |> MemTable.remove("handlebars", elapsed_tombstone_ts)

    ss_tables =
      for mem_table <- [mem_table1, mem_table2, mem_table3] do
        file_meta = %FileMeta{dir: dir, number: Utils.now()}

        mem_table
        |> SSTable.flush(file_meta)
        |> elem(1)
      end

    assert {:ok, %FileMeta{size: size} = file_meta} = SSTable.merge(ss_tables, file_meta)
    assert size > 0
    assert {:ok, ss_table} = SSTable.from_path(file_meta)
    refute SSTable.contains?(ss_table, "unknown")
    assert SSTable.contains?(ss_table, "handiwork")
    refute SSTable.contains?(ss_table, "handlebars")
    assert %Entry{key: "handful", value: "44662"} = SSTable.get!(ss_table, "handful")
    assert %Entry{key: "handicap", value: "70836"} = SSTable.get!(ss_table, "handicap")
  end

  defp flush(mem_table, dir) do
    mem_table
    |> SSTable.flush(dir)
    |> elem(1)
    |> SSTable.from_path()
    |> elem(1)
  end
end
