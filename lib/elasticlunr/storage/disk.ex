defmodule Elasticlunr.Storage.Disk do
  @moduledoc """
  This storage provider writes data to the local disk of the running application.
  ```elixir
  config :elasticlunr,
    storage: Elasticlunr.Storage.Disk
  config :elasticlunr, Elasticlunr.Storage.Disk,
    directory: "/path/to/project/storage"
  ```
  """
  use Elasticlunr.Storage

  alias Elasticlunr.{DB, Deserializer, Index, Logger, Serializer}

  @data_file_ext "data"
  @index_file_ext "index"

  @extensions [@data_file_ext, @index_file_ext]

  @impl true
  def write(%Index{db: db, name: name} = index) do
    directory = config(:directory, ".")
    data = Serializer.serialize(index)

    with %{data: data_file, index: index_file} <- filenames(directory, name),
         :ok <- DB.to(db, file: data_file) do
      write_serialized_index_to_file(index_file, data)
    end
  end

  @impl true
  def read(name) do
    directory = config(:directory, ".")
    %{data: data_file, index: index_file} = filenames(directory, name)

    index =
      File.stream!(index_file, ~w[compressed]a)
      |> Deserializer.deserialize()

    with %Index{db: db} <- index,
         {:ok, db} <- DB.from(db, file: data_file) do
      Index.update_documents_size(%{index | db: db})
    else
      false ->
        Logger.error("unable to load data for index #{index.name}")
        index
    end
  end

  @impl true
  def load_all do
    files()
    |> Stream.filter(&String.ends_with?(&1, @index_file_ext))
    |> Stream.map(fn file ->
      name = without_ext(file, @index_file_ext)
      read(name)
    end)
  end

  @impl true
  def delete(name) do
    directory = config(:directory, ".")
    %{data: data_file, index: index_file} = filenames(directory, name)

    with :ok <- File.rm(index_file) do
      File.rm(data_file)
    end
  end

  @spec files() :: list(binary())
  def files do
    directory = config(:directory, ".")
    extensions = Enum.map_join(@extensions, ",", & &1)
    match = Path.join(directory, "*.{#{extensions}}")

    Path.wildcard(match)
    |> Enum.map(&Path.expand/1)
  end

  @spec write_serialized_index_to_file(binary(), Enum.t()) :: :ok
  def write_serialized_index_to_file(path, data) do
    data
    |> Stream.into(File.stream!(path, ~w[compressed]a), &"#{&1}\n")
    |> Stream.run()
  end

  defp filenames(directory, name) do
    %{
      index: Path.join(directory, "#{name}.#{@index_file_ext}"),
      data: Path.join(directory, "#{name}.#{@data_file_ext}") |> String.to_charlist()
    }
  end

  defp without_ext(file, ext), do: Path.basename(file, ".#{ext}")
end
