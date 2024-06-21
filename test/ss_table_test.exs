defmodule Elasticlunr.SSTableTest do
  use ExUnit.Case, async: true

  alias Elasticlunr.FileMeta
  alias Elasticlunr.MemTable
  alias Elasticlunr.SSTable
  alias Elasticlunr.SSTable.Entry
  alias Elasticlunr.Utils

  import Elasticlunr.Fixture

  setup do
    dir = tmp_dir!()

    mem_table =
      %MemTable{}
      |> MemTable.set("key", "value", 1)
      |> MemTable.set("key1", "value1", 2)

    on_exit(fn -> File.rm_rf(dir) end)

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

  test "get!/2", %{dir: dir, mem_table: mem_table} do
    ss_table = flush(mem_table, dir)

    assert %Entry{key: "key"} = SSTable.get!(ss_table, "key")
    assert %Entry{key: "key1"} = SSTable.get!(ss_table, "key1")
    refute SSTable.get!(ss_table, "unknown")
  end

  test "flush/2", %{dir: dir, mem_table: mem_table} do
    assert {:ok, [%FileMeta{size: size}]} = SSTable.flush(mem_table, dir, &Utils.now/0)
    assert size > 0
  end

  test "from_path/1", %{dir: dir, mem_table: mem_table} do
    mem_table = MemTable.remove(mem_table, "key", Utils.now())

    assert {:ok, [file_meta]} = SSTable.flush(mem_table, dir, &Utils.now/0)
    assert {:ok, ss_table} = SSTable.from_path(file_meta)
    assert %Entry{key: "key", deleted: true} = SSTable.get!(ss_table, "key")
  end

  test "merge/1", %{dir: dir} do
    elapsed_tombstone_ts =
      DateTime.utc_now()
      |> DateTime.add(-10, :day)
      |> DateTime.to_unix(:microsecond)

    mem_table1 =
      %MemTable{}
      |> MemTable.set("handbag", "8786", Utils.now())
      |> MemTable.set("handful", "40308", Utils.now())
      |> MemTable.set("handicap", "65995", Utils.now())
      |> MemTable.set("handkerchief", "16324", Utils.now())

    mem_table2 =
      %MemTable{}
      |> MemTable.set("handcuffs", "2729", Utils.now())
      |> MemTable.set("handful", "42307", Utils.now())
      |> MemTable.set("handicap", "67884", Utils.now())
      |> MemTable.set("handkerchief", "20952", Utils.now())

    mem_table3 =
      %MemTable{}
      |> MemTable.set("handful", "44662", Utils.now())
      |> MemTable.set("handicap", "70836", Utils.now())
      |> MemTable.set("handiwork", "45521", Utils.now())
      |> MemTable.remove("handkerchief", Utils.now())
      |> MemTable.remove("handlebars", elapsed_tombstone_ts)

    ss_tables =
      for mem_table <- [mem_table1, mem_table2, mem_table3] do
        mem_table
        |> SSTable.flush(dir, &Utils.now/0)
        |> elem(1)
      end

    assert {:ok, [%FileMeta{size: size} = file_meta]} =
             ss_tables
             |> Enum.flat_map(& &1)
             # setting tombstone_ttl to 1s makes sure deleted entries are removed permanently
             |> SSTable.merge(dir, &Utils.now/0, tombstone_ttl: 1)

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
    |> SSTable.flush(dir, &Utils.now/0)
    |> elem(1)
    |> List.first()
    |> SSTable.from_path()
    |> elem(1)
  end
end
