defmodule Elasticlunr.Storage.S3 do
  @moduledoc """
  This provider writes to indexes to an s3 project. To use, you need
  to include necessary s3 dependencies, see [repository](https://github.com/ex-aws/ex_aws_s3).

  ```elixir
  config :elasticlunr,
    storage: Elasticlunr.Storage.S3

  config :elasticlunr, Elasticlunr.Storage.S3,
    bucket: "elasticlunr",
    access_key_id: "minioadmin",
    secret_access_key: "minioadmin",
    scheme: "http://", # optional
    host: "192.168.0.164", # optional
    port: 9000 # optional
  ```
  """
  use Elasticlunr.Storage

  alias ExAws.S3
  alias Elasticlunr.{Index, Deserializer, Serializer}

  @impl true
  def load_all do
    config(:bucket)
    |> S3.list_objects_v2()
    |> ExAws.stream!(config_all())
    |> Stream.map(fn %{key: file} ->
      name = Path.basename(file, ".index")

      read(name)
    end)
  end

  @impl true
  def write(%Index{name: name} = index) do
    bucket = config(:bucket)
    object = "#{name}.index"
    data = Serializer.serialize(index)

    with path <- tmp_file("#{name}.index"),
         :ok <- write_to_file(data, path),
         {:ok, _} <- upload_object(bucket, object, path) do
      :ok
    end
  end

  @impl true
  def read(name) do
    bucket = config(:bucket)
    object = "#{name}.index"

    with path <- tmp_file("#{name}.index"),
         {:ok, _} <- download_object(bucket, object, path) do
      File.stream!(path, ~w[compressed]a)
      |> Deserializer.deserialize()
    end
  end

  @impl true
  def delete(name) do
    bucket = config(:bucket)

    bucket
    |> S3.delete_object("#{name}.index")
    |> ExAws.request(config_all())
    |> case do
      {:ok, _} ->
        :ok

      err ->
        err
    end
  end

  defp write_to_file(data, path) do
    data
    |> Stream.into(File.stream!(path, ~w[compressed]a), &"#{&1}\n")
    |> Stream.run()
  end

  defp download_object(bucket, object, file) do
    bucket
    |> S3.download_file(object, file)
    |> ExAws.request(config_all())
  end

  defp upload_object(bucket, object, path) do
    path
    |> S3.Upload.stream_file()
    |> S3.upload(bucket, object)
    |> ExAws.request(config_all())
  end

  defp tmp_file(file) do
    Path.join(System.tmp_dir!(), file)
  end
end
