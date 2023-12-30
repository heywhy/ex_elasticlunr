defmodule Elasticlunr.Server.Writer do
  use GenServer

  alias Elasticlunr.Index.Writer

  require Logger

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    dir = Keyword.fetch!(opts, :dir)
    schema = Keyword.fetch!(opts, :schema)
    mt_max_size = Keyword.fetch!(opts, :mem_table_max_size)

    {:ok, Writer.new(dir, schema, mt_max_size)}
  end

  # Callbacks
  @impl true
  def handle_call({:save, document}, _from, %Writer{} = writer) do
    {document, writer} = Writer.save(writer, document)

    {:reply, document, write_to_disk_if_needed(writer)}
  end

  def handle_call({:save_all, documents}, _from, %Writer{} = writer) do
    writer = Writer.save_all(writer, documents)

    {:reply, :ok, write_to_disk_if_needed(writer)}
  end

  def handle_call({:delete, id}, _from, %Writer{} = writer) do
    case Writer.remove(writer, id) do
      {:ok, writer} -> {:reply, :ok, write_to_disk_if_needed(writer)}
      error -> {:reply, error, writer}
    end
  end

  def handle_call({:get, id}, _from, %Writer{} = writer) do
    {:reply, Writer.get(writer, id), writer}
  end

  @impl true
  def terminate(reason, %Writer{schema: schema} = writer) do
    :ok = Writer.close(writer)

    Logger.info("Terminating writer process for #{schema.name} due to #{inspect(reason)}")
  end

  defp write_to_disk_if_needed(%Writer{} = writer) do
    # TODO: Asynchronously flush to disk
    case Writer.buffer_filled?(writer) do
      true -> Writer.flush(writer)
      false -> writer
    end
  end
end
