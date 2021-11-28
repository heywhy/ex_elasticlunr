defmodule Elasticlunr.Storage.Disk do
  use Elasticlunr.Storage

  alias Elasticlunr.{Deserializer, Index, Serializer}

  @impl true
  def write(%Index{name: name} = index, opts \\ []) do
    root_path = config(opts, :directory, ".")
    path = Path.join(root_path, "#{name}.index")
    data = Serializer.serialize(index)

    data
    |> Stream.into(File.stream!(path, ~w[compressed]a), &"#{&1}\n")
    |> Stream.run()
  end

  @impl true
  def read(name, opts \\ []) do
    root_path = config(opts, :directory, ".")
    file = Path.join(root_path, "#{name}.index")

    File.stream!(file, ~w[compressed]a)
    |> Deserializer.deserialize()
  end
end
