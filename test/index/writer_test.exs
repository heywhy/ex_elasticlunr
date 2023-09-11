defmodule Elasticlunr.Index.WriterTest do
  use ExUnit.Case, async: true

  alias Box.MemTable
  alias Box.Index.Writer
  alias Elasticlunr.Book

  import Elasticlunr.Fixture

  setup do
    dir = tmp_dir!()

    opts = [
      dir: dir,
      mem_table_max_size: 500,
      schema: Book.__schema__()
    ]

    pid = start_supervised!({Writer, opts})

    [dir: dir, pid: pid]
  end

  test "save document", %{pid: pid} do
    document = new_book()

    refute document.id
    assert {:ok, saved} = GenServer.call(pid, {:save, document})
    assert saved.id
    assert document.title == saved.title
  end

  test "update document", %{pid: pid} do
    document = new_book(id: FlakeId.get())

    assert {:ok, saved} = GenServer.call(pid, {:save, document})
    assert document.id == saved.id
    assert document.title == saved.title
  end

  test "retrieve document", %{pid: pid} do
    {:ok, document} = GenServer.call(pid, {:save, new_book()})

    assert ^document = GenServer.call(pid, {:get, document.id})
    refute GenServer.call(pid, {:get, "unknown"})
  end

  test "delete document", %{pid: pid} do
    {:ok, document} = GenServer.call(pid, {:save, new_book()})

    assert ^document = GenServer.call(pid, {:get, document.id})
    assert :ok = GenServer.call(pid, {:delete, document.id})
    refute GenServer.call(pid, {:get, document.id})
  end

  test "flush memtable when maxed", %{pid: pid, dir: dir} do
    Stream.repeatedly(&new_book/0)
    |> Stream.each(&GenServer.call(pid, {:save, &1}))
    |> Enum.take(10)

    assert segments = MemTable.list(dir)
    refute Enum.empty?(segments)
    assert Enum.count(segments) >= 2
  end
end
