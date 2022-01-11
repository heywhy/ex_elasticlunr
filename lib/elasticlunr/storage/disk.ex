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

  alias Elasticlunr.{Deserializer, Index, Serializer}

  @impl true
  def write(%Index{name: name} = index) do
    root_path = config(:directory, ".")
    path = Path.join(root_path, "#{name}.index")
    data = Serializer.serialize(index)

    data
    |> Stream.into(File.stream!(path, ~w[compressed]a), &"#{&1}\n")
    |> Stream.run()
  end

  @impl true
  def read(name) do
    root_path = config(:directory, ".")
    file = Path.join(root_path, "#{name}.index")

    File.stream!(file, ~w[compressed]a)
    |> Deserializer.deserialize()
  end

  @impl true
  def load_all do
    Stream.map(files(), fn file ->
      name = Path.basename(file, ".index")
      read(name)
    end)
  end

  @impl true
  def delete(name) do
    root_path = config(:directory, ".")
    file = Path.join(root_path, "#{name}.index")

    File.rm(file)
  end

  @spec files() :: list(binary())
  def files do
    root_path = config(:directory, ".")
    match = Path.join(root_path, "*.index")

    Path.wildcard(match)
    |> Enum.map(&Path.expand/1)
  end
end
