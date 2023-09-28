defmodule Elasticlunr.Index.ReaderTest do
  use ExUnit.Case, async: true

  alias Box.Fs
  alias Box.Index.Reader
  alias Box.Index.Writer
  alias Box.SSTable
  alias Box.SSTable.Entry
  alias Elasticlunr.Book

  import Elasticlunr.Fixture
  import Liveness

  setup do
    dir = tmp_dir!()

    opts = [
      dir: dir,
      # specify smaller value so that memtable can be immediately flushed
      mem_table_max_size: 10,
      schema: Book.__schema__()
    ]

    start_supervised!({Fs, dir})

    writer = start_supervised!({Writer, opts})
    pid = start_supervised!({Reader, dir: dir})

    document = GenServer.call(writer, {:save, new_book()})

    [dir: dir, pid: pid, writer: writer, document: document]
  end

  test "retrieve document", %{pid: pid, document: document} do
    assert %Entry{} = eventually(fn -> GenServer.call(pid, {:get, document.id}) end)
    refute GenServer.call(pid, {:get, "unknown"})
  end

  test "update internals when a segment is deleted", %{dir: dir, pid: pid, document: document} do
    dir
    |> SSTable.list()
    |> Enum.each(&File.rm_rf!/1)

    assert eventually(fn -> GenServer.call(pid, {:get, document.id}) == nil end)
  end

  test "update internals when a segment is created", %{pid: pid, writer: writer} do
    document = GenServer.call(writer, {:save, new_book()})

    assert %Entry{key: key} = eventually(fn -> GenServer.call(pid, {:get, document.id}) end)
    assert key == document.id
  end
end
