defmodule Elasticlunr.SSTableTest do
  use ExUnit.Case, async: true

  alias Box.MemTable
  alias Box.SSTable
  alias Box.SSTable.Entry

  import Elasticlunr.Fixture

  setup do
    dir = tmp_dir!()

    mem_table =
      MemTable.new()
      |> MemTable.set("key", "value", 1)
      |> MemTable.set("key1", "value1", 2)

    [dir: dir, mem_table: mem_table]
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

  test "from_file/1", %{dir: dir, mem_table: mem_table} do
    mem_table = MemTable.remove(mem_table, "key", 3)

    assert ss_table = flush(mem_table, dir)
    assert %Entry{key: "key", deleted: true} = SSTable.get(ss_table, "key")
  end

  defp flush(mem_table, dir) do
    mem_table
    |> SSTable.flush(dir)
    |> SSTable.from_file()
  end
end
