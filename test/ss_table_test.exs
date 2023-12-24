defmodule Elasticlunr.SSTableTest do
  use ExUnit.Case, async: true

  alias Elasticlunr.MemTable
  alias Elasticlunr.SSTable
  alias Elasticlunr.SSTable.Entry
  alias Elasticlunr.Utils

  import Elasticlunr.Fixture

  setup do
    dir = tmp_dir!()

    mem_table =
      MemTable.new()
      |> MemTable.set("key", "value", 1)
      |> MemTable.set("key1", "value1", 2)

    [dir: dir, mem_table: mem_table]
  end

  test "count/1", %{dir: dir, mem_table: mem_table} do
    ss_table = flush(mem_table, dir)

    assert SSTable.count(ss_table) == 2
  end

  test "contains?/2", %{dir: dir, mem_table: mem_table} do
    ss_table = flush(mem_table, dir)

    assert SSTable.contains?(ss_table, "key")
    assert SSTable.contains?(ss_table, "key1")
    refute SSTable.contains?(ss_table, "unknown")
  end

  test "get/2", %{dir: dir, mem_table: mem_table} do
    ss_table = flush(mem_table, dir)

    assert %Entry{key: "key"} = SSTable.get(ss_table, "key")
    assert %Entry{key: "key1"} = SSTable.get(ss_table, "key1")
    refute SSTable.get(ss_table, "unknown")
  end

  test "flush/2", %{dir: dir, mem_table: mem_table} do
    assert file = SSTable.flush(mem_table, dir)
    assert %File.Stat{size: size} = File.stat!(file)
    assert size > 0
  end

  test "list/2", %{dir: dir, mem_table: mem_table} do
    assert [] = SSTable.list(dir)
    assert %SSTable{path: file} = flush(mem_table, dir)
    assert [^file] = SSTable.list(dir)
  end

  test "from_path/1", %{dir: dir, mem_table: mem_table} do
    mem_table = MemTable.remove(mem_table, "key", 3)

    assert path = SSTable.flush(mem_table, dir)
    assert ss_table = SSTable.from_path(path)
    assert %Entry{key: "key", deleted: true} = SSTable.get(ss_table, "key")
  end

  test "merge/1", %{dir: dir} do
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

    for mem_table <- [mem_table1, mem_table2, mem_table3] do
      SSTable.flush(mem_table, dir)
    end

    ss_tables = SSTable.list(dir)

    assert path = SSTable.merge(ss_tables, dir)
    assert ss_table = SSTable.from_path(path)
    refute SSTable.contains?(ss_table, "unknown")
    assert SSTable.contains?(ss_table, "handiwork")
    refute SSTable.contains?(ss_table, "handlebars")
    assert %Entry{key: "handful", value: "44662"} = SSTable.get(ss_table, "handful")
    assert %Entry{key: "handicap", value: "70836"} = SSTable.get(ss_table, "handicap")
  end

  defp flush(mem_table, dir) do
    mem_table
    |> SSTable.flush(dir)
    |> SSTable.from_path()
  end
end
