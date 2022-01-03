defimpl Elasticlunr.Serializer, for: Elasticlunr.Pipeline do
  alias Elasticlunr.Pipeline

  def serialize(%Pipeline{callback: callback}, opts) do
    cache = Keyword.get(opts, :pipeline, %{})

    callback
    |> Enum.map(&Map.get(cache, &1, &1))
    |> Enum.join(",")
  end
end

defimpl Elasticlunr.Serializer, for: Elasticlunr.Field do
  alias Elasticlunr.{Field, Serializer}

  def serialize(
        %Field{
          pipeline: pipeline,
          store: store_documents,
          store_positions: store_positions
        },
        opts
      ) do
    name = Keyword.get(opts, :name)
    pipeline = Serializer.serialize(pipeline, opts)

    "field#name:#{name}|pipeline:#{pipeline}|store_documents:#{store_documents}|store_positions:#{store_positions}"
  end
end

defimpl Elasticlunr.Serializer, for: Elasticlunr.Index do
  alias Elasticlunr.{Field, Index, Pipeline, Serializer}

  def serialize(%Index{fields: fields, name: name, pipeline: pipeline, ref: ref}, _opts) do
    %Pipeline{callback: callback} = pipeline
    pipeline = Serializer.serialize(pipeline)

    {_, pipeline_map} =
      Enum.reduce(callback, {0, %{}}, fn callback, {index, map} ->
        {index + 1, Map.put(map, callback, index)}
      end)

    settings = "settings#name:#{name}|ref:#{ref}|pipeline:#{pipeline}"

    fields_settings =
      Stream.map(fields, fn {name, field} ->
        Serializer.serialize(field, name: name, pipeline: pipeline_map)
      end)

    fields_documents =
      Stream.map(fields, fn {name, %Field{documents: documents}} ->
        {:ok, data} = Jason.encode(documents)
        "documents##{name}|#{data}"
      end)

    tokens =
      fields
      |> Stream.map(fn {name, field} ->
        Field.all_tokens(field)
        |> Stream.map(fn token ->
          {:ok, data} = Jason.encode(token)
          "token#field:#{name}|#{data}"
        end)
      end)
      |> Stream.flat_map(& &1)

    [settings, fields_settings, fields_documents, tokens]
    |> Stream.flat_map(fn
      list when is_list(list) -> list
      value when is_binary(value) -> [value]
      value -> value
    end)
  end
end

defimpl Jason.Encoder, for: Tuple do
  def encode({start_pos, end_pos}, opts) do
    [start_pos, end_pos]
    |> Jason.Encode.list(opts)
  end
end

defimpl Elasticlunr.Deserializer, for: Stream do
  alias Elasticlunr.Deserializer.Parser

  def deserialize(data) do
    Parser.process(data)
  end
end
