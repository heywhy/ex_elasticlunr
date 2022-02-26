defprotocol Elasticlunr.Deserializer do
  @spec deserialize(Enum.t()) :: Elasticlunr.Index.t()
  def deserialize(data)
end

defmodule Elasticlunr.Deserializer.Parser do
  alias Elasticlunr.{Field, Index, Pipeline}

  @spec process(Enum.t()) :: Index.t()
  def process(data) do
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
    opts =
      to_options(opts)
      |> Keyword.put_new(:on_conflict, "index")

    {_, pipeline_map} =
      opts[:pipeline]
      |> String.split(",")
      |> Enum.reduce({0, %{}}, fn callback, {index, map} ->
        {index + 1, Map.put(map, to_string(index), String.to_atom(callback))}
      end)

    opts =
      opts
      |> Keyword.replace(:pipeline, parse_pipeline(opts[:pipeline]))
      |> Keyword.replace(:on_conflict, String.to_atom(opts[:on_conflict]))

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
