defprotocol Elasticlunr.Deserializer do
  @spec deserialize(Enum.t()) :: Elasticlunr.Index.t()
  def deserialize(data)
end

defmodule Elasticlunr.Deserializer.Parser do
  alias Elasticlunr.{Index, Pipeline}

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
    |> case do
      {%Index{} = index, _} ->
        index

      result ->
        result
    end
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

  defp parse("db", acc, _), do: acc

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

  defp parse(_, acc, _), do: acc

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
