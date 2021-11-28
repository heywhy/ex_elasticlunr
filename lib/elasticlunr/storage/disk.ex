defmodule Elasticlunr.Storage.Disk do
  use Elasticlunr.Storage, :disk

  alias Elasticlunr.{Deserializer, Serializer}

  @impl true
  def write(name, index) do
    root_path = config(:dir, ".")
    path = Path.join(root_path, "#{name}.index")
    data = Serializer.serialize(index)

    data
    |> Stream.into(File.stream!(path, ~w[compressed]a), &"#{&1}\n")
    |> Stream.run()
  end

  @impl true
  def read(name) do
    root_path = config(:dir, ".")
    file = Path.join(root_path, "#{name}.index")

    File.stream!(file, ~w[compressed]a)
    |> Deserializer.deserialize()
  end
end
