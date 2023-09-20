defmodule Elasticlunr.SSTableTest do
  use ExUnit.Case, async: true

  alias Box.MemTable
  alias Box.SSTable
  alias Box.SSTable.Entry
  alias Box.Utils

  import Elasticlunr.Fixture

  setup do
    dir = tmp_dir!()

    mem_table =
      MemTable.new()
      |> MemTable.set("key", "value", 1)
      |> MemTable.set("key1", "value1", 2)

    [dir: dir, mem_table: mem_table]
  end

  test "contains?/2", %{dir: dir, mem_table: mem_table} do
    ss_table = flush(mem_table, dir)

    assert SSTable.contains?(ss_table, "key")
    assert SSTable.contains?(ss_table, "key1")
    refute SSTable.contains?(ss_table, "unknown")
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
    mem_table1 =
      MemTable.new()
      |> MemTable.set("handbag", "8786", Utils.now())
      |> MemTable.set("handful", "40308", Utils.now())
      |> MemTable.set("handicap", "65995", Utils.now())

    mem_table2 =
      MemTable.new()
      |> MemTable.set("handcuffs", "2729", Utils.now())
      |> MemTable.set("handful", "42307", Utils.now())
      |> MemTable.set("handicap", "67884", Utils.now())

    mem_table3 =
      MemTable.new()
      |> MemTable.set("handful", "44662", Utils.now())
      |> MemTable.set("handicap", "70836", Utils.now())
      |> MemTable.set("handiwork", "45521", Utils.now())

    for mem_table <- [mem_table1, mem_table2, mem_table3] do
      SSTable.flush(mem_table, dir)
    end

    assert path = SSTable.merge(dir)
    assert ss_table = SSTable.from_path(path)
    assert SSTable.contains?(ss_table, "handiwork")
  end

  defp flush(mem_table, dir) do
    mem_table
    |> SSTable.flush(dir)
    |> SSTable.from_path()
  end
end
