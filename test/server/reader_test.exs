defmodule Elasticlunr.Server.ReaderTest do
  use ExUnit.Case, async: true

  alias Elasticlunr.Book
  alias Elasticlunr.PubSub
  alias Elasticlunr.Server.Reader
  alias Elasticlunr.Server.Writer

  import Elasticlunr.Fixture
  import Elasticlunr.TestUtils
  import Liveness

  setup do
    dir = tmp_dir!()
    %{options: options} = schema = Book.__schema__()
    # specify smaller value so that memtable can be immediately flushed
    options = %{options | max_buffer_size: 10}

    opts = [
      dir: dir,
      schema: %{schema | options: options}
    ]

    writer = start_supervised!({Writer, opts})
    pid = start_supervised!({Reader, dir: dir, schema: schema})

    document = GenServer.call(writer, {:save, new_book()})

    [dir: dir, pid: pid, schema: schema, writer: writer, document: document]
  end

  test "retrieve document", %{pid: pid, document: document, writer: writer} do
    GenServer.call(writer, {:save, new_book()})

    assert ^document = eventually(fn -> GenServer.call(pid, {:get, document.id}) end)
    refute GenServer.call(pid, {:get, "unknown"})
  end

  test "having key in multiple sstables returns most recent", %{
    dir: dir,
    pid: pid,
    writer: writer,
    document: document
  } do
    for _ <- 1..4 do
      GenServer.call(writer, {:save, new_book(id: document.id)})
    end

    # Add an extra write to force extra generated sstable
    GenServer.call(writer, {:save, new_book()})

    assert eventually(fn -> ss_tables(dir) |> Enum.count() == 5 end)
    assert eventually(fn -> GenServer.call(pid, {:get, document.id}) end)
  end

  test "update internals when a segment is created", %{pid: pid, writer: writer} do
    document = GenServer.call(writer, {:save, new_book()})

    # Add an extra write to force generate sstable
    GenServer.call(writer, {:save, new_book()})

    assert entry = eventually(fn -> GenServer.call(pid, {:get, document.id}) end)
    assert entry.id == document.id
  end

  test "starting reader loads state from manifest", %{dir: dir, schema: schema, writer: writer} do
    document = GenServer.call(writer, {:save, new_book()})

    # Add an extra write to force generate sstable
    GenServer.call(writer, {:save, new_book()})

    assert :ok = stop_supervised!(Reader)
    assert pid = start_supervised!({Reader, dir: dir, schema: schema})
    assert entry = eventually(fn -> GenServer.call(pid, {:get, document.id}) end)
    assert entry.id == document.id
  end

  test "update internals when a segment is deleted", %{
    dir: dir,
    pid: pid,
    document: document,
    schema: schema,
    writer: writer
  } do
    GenServer.call(writer, {:save, new_book()})

    # Add an extra write to force generate sstable
    GenServer.call(writer, {:save, new_book()})

    ss_tables = ss_tables(dir)

    assert eventually(fn -> GenServer.call(pid, {:get, document.id}) end)
    Enum.each(ss_tables, &PubSub.publish(schema.name, :file_deleted, &1))
    assert eventually(fn -> GenServer.call(pid, {:get, document.id}) == nil end)
  end
end
