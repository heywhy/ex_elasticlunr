defmodule Elasticlunr.MemTableTest do
  use ExUnit.Case, async: true

  alias Box.MemTable
  alias Box.MemTable.Entry

  setup do
    mem_table =
      MemTable.new()
      |> MemTable.set("key", "value", 1)
      |> MemTable.set("key1", "value1", 2)

    [mem_table: mem_table]
  end

  test "set/4 adds a new entry", %{mem_table: mem_table} do
    mem_table = MemTable.set(mem_table, "key2", "value2", 3)

    assert 3 = MemTable.length(mem_table)
  end

  test "set/4 updates existing entry", %{mem_table: mem_table} do
    mem_table = MemTable.set(mem_table, "key", "value1", 2)

    assert 2 = MemTable.length(mem_table)
    assert %Entry{key: "key", value: "value1", timestamp: 2} = MemTable.get(mem_table, "key")
  end

  test "remove/3 sets entry to deleted", %{mem_table: mem_table} do
    mem_table = MemTable.remove(mem_table, "key", 3)

    assert 2 = MemTable.length(mem_table)
    assert %Entry{key: "key", deleted: true, value: nil} = MemTable.get(mem_table, "key")
  end

  test "remove/3 adds a deletion entry for missing key", %{mem_table: mem_table} do
    mem_table = MemTable.remove(mem_table, "key2", 3)

    assert 3 = MemTable.length(mem_table)
    assert %Entry{key: "key2", deleted: true} = MemTable.get(mem_table, "key2")
  end

  test "stream/1", %{mem_table: mem_table} do
    assert stream = MemTable.stream(mem_table)
    assert Enum.count(stream) == 2
    assert Enum.all?(stream, &(&1.key in ["key", "key1"]))
  end
end
