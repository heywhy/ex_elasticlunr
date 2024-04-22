defmodule Elasticlunr.Server.WriterTest do
  use ExUnit.Case, async: true

  alias Elasticlunr.Book
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Filename
  alias Elasticlunr.Fs
  alias Elasticlunr.Manifest
  alias Elasticlunr.Manifest.Changes
  alias Elasticlunr.Schema
  alias Elasticlunr.Server.Writer
  alias Elasticlunr.SSTable
  alias Elasticlunr.Utils
  alias Elasticlunr.Wal

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
    (&new_book/0)
    |> Stream.repeatedly()
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

  test "existing logs gets compacted on startup", %{dir: dir, opts: opts, pid: pid} do
    %{writer: writer} = :sys.get_state(pid)
    {number, _manifest} = Manifest.new_file_number(writer.manifest)

    stop_supervised!(Writer)

    wal = Wal.create(dir, number)
    book = new_book(id: Utils.new_id())
    schema = Keyword.fetch!(opts, :schema)

    (&new_book/0)
    |> Stream.repeatedly()
    |> Stream.take(10)
    |> Enum.reduce(write_to_wal(book, wal, schema), fn book, {:ok, wal} ->
      write_to_wal(book, wal, schema)
    end)

    assert :ok = Wal.close(wal)

    assert {:ok, pid} = start_supervised({Writer, opts})
    assert %{writer: writer} = :sys.get_state(pid)
    assert Manifest.current_log(writer.manifest) == 6
    assert number = Manifest.known_files(writer.manifest) |> MapSet.to_list() |> List.first()
    assert file_meta = Manifest.find_file(writer.manifest, number)
    assert {:ok, ss_table} = SSTable.from_path(file_meta)
    assert %{value: value} = SSTable.get(ss_table, book.id)
    assert document = Schema.binary_to_document(opts[:schema], value)
    assert book == struct!(Book, Map.put(document, :id, book.id))
  end

  test "failure on flush memtable task is handled", %{dir: dir, opts: opts} do
    stop_supervised!(Writer)

    # Implementing the below function allows us to simulate when a task didn't return
    flush_fn = fn %{manifest: manifest} = writer ->
      owner = self()
      pid = spawn(fn -> nil end)
      ref = Process.monitor(pid)
      task = %Task{pid: pid, owner: owner, ref: ref, mfa: {Writer, :flush_asyc, 1}}
      {_file_number, manifest} = Manifest.new_file_number(manifest)

      {task, %{writer | manifest: manifest}}
    end

    pid =
      opts
      |> Keyword.put(:flush_fn, flush_fn)
      |> then(&start_supervised!({Writer, &1}))

    (&new_book/0)
    |> Stream.repeatedly()
    |> Stream.each(&GenServer.call(pid, {:save, &1}))
    |> Enum.take(4)

    assert Process.alive?(pid)

    assert [{:log, number}, _] =
             Fs.db_files(dir)
             |> Enum.map(&Filename.parse/1)
             |> Enum.filter(&match?({:log, _}, &1))

    assert {:ok, %Manifest{log_number: ^number}} = read_manifest(dir)
  end

  defp write_to_wal(book, wal, schema) do
    id = book.id || Utils.new_id()

    book
    |> Map.drop([:__struct__, :id])
    |> then(&Schema.document_to_binary(schema, &1))
    |> then(&Wal.set(wal, id, &1, Utils.now()))
  end

  defp read_manifest(dir) do
    dir
    |> Filename.current()
    |> File.read!()
    |> then(&Path.join(dir, &1))
    |> Manifest.from_path()
  end
end
