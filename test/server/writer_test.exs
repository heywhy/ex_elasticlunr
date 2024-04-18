defmodule Elasticlunr.Server.WriterTest do
  use ExUnit.Case, async: true

  alias Elasticlunr.Book
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Filename
  alias Elasticlunr.Manifest
  alias Elasticlunr.Manifest.Changes
  alias Elasticlunr.Server.Writer
  alias Elasticlunr.SSTable
  alias Elasticlunr.Utils

  import Elasticlunr.Fixture
  import Liveness

  setup do
    dir = tmp_dir!()

    opts = [
      dir: dir,
      mem_table_max_size: 500,
      schema: Book.__schema__()
    ]

    pid = start_supervised!({Writer, opts})

    [dir: dir, opts: opts, pid: pid]
  end

  test "save document", %{pid: pid} do
    document = new_book()

    refute document.id
    assert saved = GenServer.call(pid, {:save, document})
    assert saved.id
    assert document.title == saved.title
  end

  test "save multiple documents", %{pid: pid} do
    documents = [new_book(id: Utils.new_id()), new_book(id: Utils.new_id())]

    assert :ok = GenServer.call(pid, {:save_all, documents})
    assert Enum.all?(documents, &match?(%{id: _id}, GenServer.call(pid, {:get, &1.id})))
  end

  test "update document", %{pid: pid} do
    document = GenServer.call(pid, {:save, new_book()})

    assert saved = GenServer.call(pid, {:save, document})
    assert document.id == saved.id
    assert document.title == saved.title
  end

  test "retrieve document", %{pid: pid} do
    document = GenServer.call(pid, {:save, new_book()})

    assert ^document = GenServer.call(pid, {:get, document.id})
    refute GenServer.call(pid, {:get, "unknown"})
  end

  test "delete document", %{pid: pid} do
    document = GenServer.call(pid, {:save, new_book()})

    assert ^document = GenServer.call(pid, {:get, document.id})
    assert :ok = GenServer.call(pid, {:delete, document.id})
    refute GenServer.call(pid, {:get, document.id})
  end

  test "recover log files on restart", %{opts: opts, pid: pid} do
    document1 = GenServer.call(pid, {:save, new_book()})
    document2 = GenServer.call(pid, {:save, new_book()})

    assert :ok = stop_supervised(Writer)
    pid = start_supervised!({Writer, opts})

    assert ^document1 = GenServer.call(pid, {:get, document1.id})
    assert ^document2 = GenServer.call(pid, {:get, document2.id})
  end

  test "flush memtable when maxed", %{pid: pid, dir: dir} do
    Stream.repeatedly(&new_book/0)
    |> Stream.each(&GenServer.call(pid, {:save, &1}))
    |> Enum.take(10)

    assert segments = SSTable.list(dir)
    refute Enum.empty?(segments)
    assert Enum.count(segments) >= 2
  end

  test "newly created sstable is added to the manifest", %{dir: dir, pid: pid} do
    for _ <- 0..10 do
      GenServer.call(pid, {:save, new_book()})
    end

    assert eventually(fn ->
             %{writer: writer} = :sys.get_state(pid)

             dir
             |> SSTable.list()
             |> Enum.map(fn path -> Filename.parse(path) end)
             |> MapSet.new(fn {:sst, number} -> number end)
             |> Kernel.==(Manifest.known_files(writer.manifest))
           end)
  end

  test "missing files in manifest causes an error", %{dir: dir, opts: opts, pid: pid} do
    %{writer: writer} = :sys.get_state(pid)
    %{manifest: manifest} = writer

    file_meta = %FileMeta{
      number: 999,
      dir: dir,
      smallest_key: Utils.new_id(),
      largest_key: Utils.new_id()
    }

    changes = Changes.add_file(%Changes{}, file_meta)

    assert {:ok, _manifest} = Manifest.apply_and_log(manifest, changes)

    stop_supervised!(Writer)

    assert {:error, {"1 missing file(s): 999", _}} = start_supervised({Writer, opts})
  end
end
