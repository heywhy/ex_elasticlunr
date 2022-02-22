defimpl Elasticlunr.Serializer, for: Elasticlunr.Pipeline do
  alias Elasticlunr.Pipeline

  def serialize(%Pipeline{callback: callback}, opts) do
    cache = Keyword.get(opts, :pipeline, %{})

    Enum.map_join(callback, ",", &Map.get(cache, &1, &1))
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

defimpl Elasticlunr.Serializer, for: Elasticlunr.DB do
  alias Elasticlunr.DB

  def serialize(%DB{name: name, options: options}, _opts) do
    options = Enum.map_join(options, ",", &to_string(&1))

    "db#name:#{name}|options:#{options}"
  end
end

defimpl Elasticlunr.Serializer, for: Elasticlunr.Index do
  alias Elasticlunr.{Index, Serializer}

  def serialize(%Index{db: db, fields: fields, name: name, pipeline: pipeline, ref: ref}, _opts) do
    pipeline_opt = Serializer.serialize(pipeline)
    db_settings = Serializer.serialize(db)

    {_, pipeline_map} =
      Enum.reduce(pipeline.callback, {0, %{}}, fn callback, {index, map} ->
        {index + 1, Map.put(map, callback, index)}
      end)

    settings = "settings#name:#{name}|ref:#{ref}|pipeline:#{pipeline_opt}"

    fields_settings =
      Stream.map(fields, fn {name, field} ->
        Serializer.serialize(field, name: name, pipeline: pipeline_map)
      end)

    [settings, db_settings, fields_settings]
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

defimpl Elasticlunr.Deserializer, for: File.Stream do
  alias Elasticlunr.Deserializer.Parser

  def deserialize(data) do
    Parser.process(data)
  end
end
