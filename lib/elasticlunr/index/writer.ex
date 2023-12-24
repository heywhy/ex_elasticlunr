defmodule Elasticlunr.Index.Writer do
  alias Elasticlunr.MemTable
  alias Elasticlunr.MemTable.Entry
  alias Elasticlunr.Schema
  alias Elasticlunr.SSTable
  alias Elasticlunr.Utils
  alias Elasticlunr.Wal

  require Logger

  defstruct [:dir, :schema, :wal, :mem_table, :mt_max_size]

  @type t :: %__MODULE__{
          wal: Wal.t(),
          dir: Path.t(),
          schema: Schema.t(),
          mem_table: MemTable.t(),
          mt_max_size: pos_integer()
        }

  @spec new(Path.t(), Schema.t(), pos_integer()) :: t()
  def new(dir, schema, mt_max_size) do
    {wal, mem_table} = Wal.load_from_dir(dir)

    attrs = [
      dir: dir,
      wal: wal,
      schema: schema,
      mem_table: mem_table,
      mt_max_size: mt_max_size
    ]

    struct!(__MODULE__, attrs)
  end

  @spec buffer_filled?(t()) :: boolean()
  def buffer_filled?(%__MODULE__{mem_table: mem_table, mt_max_size: mt_max_size}) do
    MemTable.size(mem_table) >= mt_max_size
  end

  @spec close(t()) :: :ok | no_return()
  def close(%__MODULE__{wal: wal}) do
    Wal.close(wal)
  end

  @spec flush(t()) :: t() | no_return()
  def flush(%__MODULE__{dir: dir, mem_table: mem_table, wal: wal} = writer) do
    _path = SSTable.flush(mem_table, dir)
    :ok = Wal.delete(wal)
    %{writer | wal: Wal.create(dir), mem_table: MemTable.new()}
  end

  @spec get(t(), String.t()) :: nil | map()
  def get(%__MODULE__{mem_table: mem_table, schema: schema}, id) do
    with id <- Utils.id_from_string(id),
         %Entry{deleted: false, value: value} <- MemTable.get(mem_table, id),
         value <- Schema.binary_to_document(schema, value) do
      Map.put(value, :id, Utils.id_to_string(id))
    else
      %Entry{deleted: true} -> nil
      nil -> nil
    end
  end

  @spec remove(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def remove(%__MODULE__{mem_table: mem_table, wal: wal} = writer, id) do
    with id <- Utils.id_from_string(id),
         timestamp <- Utils.now(),
         mem_table <- MemTable.remove(mem_table, id, timestamp),
         {:ok, wal} <- Wal.remove(wal, id, timestamp),
         :ok <- Wal.flush(wal),
         writer <- %{writer | wal: wal, mem_table: mem_table} do
      {:ok, writer}
    end
  end

  @spec save(t(), map()) :: {map(), t()} | no_return()
  def save(%__MODULE__{} = writer, %{} = document) do
    {document, writer} = save_document(document, writer)

    :ok = Wal.flush(writer.wal)

    {document, writer}
  end

  @spec save_all(t(), [map()]) :: t() | no_return()
  def save_all(%__MODULE__{} = writer, documents) do
    documents
    |> Enum.reduce(writer, fn document, writer ->
      document
      |> save_document(writer)
      |> elem(1)
    end)
    |> tap(&(:ok = Wal.flush(&1.wal)))
  end

  defp save_document(document, %{schema: schema} = writer) do
    {id, document} =
      document
      # drop the struct key
      |> Map.drop([:__struct__])
      |> Map.replace_lazy(:id, fn
        nil -> Utils.new_id()
        value -> Utils.id_from_string(value)
      end)
      |> Map.pop!(:id)

    with timestamp <- Utils.now(),
         value <- Schema.document_to_binary(schema, document),
         mem_table <- MemTable.set(writer.mem_table, id, value, timestamp),
         {:ok, wal} <- Wal.set(writer.wal, id, value, timestamp),
         document <- Map.put(document, :id, Utils.id_to_string(id)) do
      {document, %{writer | wal: wal, mem_table: mem_table}}
    end
  end
end
