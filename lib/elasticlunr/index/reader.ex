defmodule Elasticlunr.Index.Reader do
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Filename
  alias Elasticlunr.Schema
  alias Elasticlunr.SSTable
  alias Elasticlunr.SSTable.Entry
  alias Elasticlunr.Utils

  require Logger

  defstruct [:dir, :schema, :segments]

  @type t :: %__MODULE__{
          dir: Path.t(),
          schema: Schema.t(),
          segments: [SSTable.t()]
        }

  @spec new(Path.t(), Schema.t(), keyword()) :: t()
  def new(dir, schema, opts \\ []) do
    attrs = [
      dir: dir,
      schema: schema,
      segments: Keyword.get(opts, :segments, [])
    ]

    struct!(__MODULE__, attrs)
  end

  @spec loaded?(t(), FileMeta.t()) :: boolean()
  def loaded?(%__MODULE__{segments: segments}, %FileMeta{dir: dir, number: number}) do
    dir
    |> Filename.ss_table(number)
    |> then(&Enum.any?(segments, fn ss_table -> ss_table.path == &1 end))
  end

  @spec add_segment(t(), FileMeta.t()) :: {:ok, t()} | {:error, File.posix()}
  def add_segment(%__MODULE__{segments: segments} = reader, %FileMeta{} = file_meta) do
    with false <- loaded?(reader, file_meta),
         {:ok, ss_table} <- SSTable.from_path(file_meta) do
      {:ok, %{reader | segments: [ss_table] ++ segments}}
    else
      true -> {:ok, reader}
      error -> error
    end
  end

  @spec get(t(), String.t()) :: map() | nil
  def get(%__MODULE__{schema: schema, segments: segments}, id) do
    id = Utils.id_from_string(id)

    segments
    |> Enum.filter(&SSTable.contains?(&1, id))
    |> Task.async_stream(&SSTable.get(&1, id))
    |> Stream.map(fn {:ok, entry} -> entry end)
    # reject nil values in case of false positive by the bloom filter
    |> Stream.reject(&is_nil/1)
    |> Enum.max_by(& &1.timestamp, &Kernel.>=/2, fn -> nil end)
    |> case do
      nil -> nil
      %Entry{key: ^id, deleted: true} -> nil
      %Entry{key: ^id} = entry -> entry_to_document(entry, schema)
    end
  end

  defp entry_to_document(%Entry{key: key, value: value}, schema) do
    schema
    |> Schema.binary_to_document(value)
    |> Map.put(:id, Utils.id_to_string(key))
  end
end
