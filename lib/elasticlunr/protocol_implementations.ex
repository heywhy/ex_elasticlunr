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

defimpl Elasticlunr.Deserializer, for: File.Stream do
  alias Elasticlunr.{Field, Index, Pipeline}

  def deserialize(data) do
    Enum.reduce(data, nil, fn line, acc ->
      [command | opts] =
        String.trim(line)
        |> String.split("#")

      case parse(command, acc, opts) do
        {%Index{}, _extra} = acc ->
          acc

        %Index{} = index ->
          index
      end
    end)
  end

  defp parse(command, acc, [opts]), do: parse(command, acc, opts)

  defp parse("settings", nil, opts) do
    opts = to_options(opts)

    {_, pipeline_map} =
      opts[:pipeline]
      |> String.split(",")
      |> Enum.reduce({0, %{}}, fn callback, {index, map} ->
        {index + 1, Map.put(map, to_string(index), String.to_atom(callback))}
      end)

    opts = Keyword.replace(opts, :pipeline, parse_pipeline(opts[:pipeline]))

    {Index.new(opts), %{pipeline: pipeline_map}}
  end

  defp parse("field", {index, extra}, opts) do
    opts = to_options(opts)

    opts =
      Enum.map(opts, fn
        {:pipeline, value} ->
          {:pipeline, parse_pipeline(value, extra[:pipeline])}

        option ->
          option
      end)

    index = Index.add_field(index, opts[:name], opts)
    {index, extra}
  end

  defp parse("documents", {index, _}, opts), do: parse("documents", index, opts)

  defp parse("documents", index, data) do
    [name | tail] = String.split(data, "|")
    [encoded_data] = tail
    field = Index.get_field(index, name)
    {:ok, documents} = Jason.decode(encoded_data)

    Index.update_field(index, name, %{field | documents: documents})
  end

  defp parse("token", index, "field:" <> data) do
    [name | tail] = String.split(data, "|")
    [encoded_data] = tail
    {:ok, token} = Jason.decode(encoded_data)

    %{"term" => term, "terms" => terms, "tf" => tf} = token

    re =
      Enum.reduce(tf, %{}, fn {doc_id, tf}, acc ->
        Map.put(acc, doc_id, %{tf: tf})
      end)

    re =
      Enum.reduce(terms, re, fn {doc_id, info}, acc ->
        val = Map.get(acc, doc_id, %{})

        val =
          case Map.get(info, "positions") do
            nil ->
              val

            positions when is_list(positions) ->
              # credo:disable-for-next-line
              positions = Enum.map(positions, fn [start | [endp]] -> {start, endp} end)

              Map.put(val, :positions, positions)
          end

        Map.put(acc, doc_id, val)
      end)

    field = Index.get_field(index, name)
    field = Field.set_token(field, term, re)

    Index.update_field(index, name, field)
  end

  defp parse_pipeline(option, cache \\ %{}) do
    callbacks =
      option
      |> String.split(",")
      |> Enum.map(fn callback ->
        Map.get_lazy(cache, callback, fn -> String.to_atom(callback) end)
      end)

    Pipeline.new(callbacks)
  end

  defp to_options(options) when is_binary(options) do
    String.split(options, "|")
    |> Enum.reduce([], fn option, acc ->
      [key | values] = String.split(option, ":")
      [value] = values
      Keyword.put(acc, String.to_atom(key), parse_value(value))
    end)
  end

  defp parse_value("true"), do: true
  defp parse_value("false"), do: false
  defp parse_value(val), do: val
end
