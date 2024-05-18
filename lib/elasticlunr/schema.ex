defmodule Elasticlunr.Schema do
  alias Elasticlunr.CompactionStrategy.SizeTiered
  alias Elasticlunr.Encoding
  alias Elasticlunr.Field
  alias Elasticlunr.Options

  @enforce_keys [:name]
  defstruct [
    :name,
    fields: %{},
    options: %Options{},
    compaction_strategy: {SizeTiered, []}
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          options: Options.t(),
          compaction_strategy: {module(), keyword()},
          fields: %{required(String.t()) => Field.t()}
        }

  @k_text_tag 1
  @k_integer_tag 2
  @k_float_tag 3
  @k_date_tag 4
  @k_array_tag 5

  defmacro options(opts) when is_list(opts) do
    quote bind_quoted: [options: opts] do
      @options struct!(Options, options)
    end
  end

  defmacro compaction(strategy, opts \\ []) do
    config = {strategy, opts}

    quote bind_quoted: [config: config] do
      @compaction_strategy config
    end
  end

  defmacro schema(name, do: block) when is_binary(name) do
    exprs =
      case block do
        {:__block__, _opts, exprs} -> exprs
        expr -> [expr]
      end

    body =
      Enum.reduce(exprs, Macro.escape(%__MODULE__{name: name}), fn expr, acc ->
        quote do
          unquote(acc) |> unquote(expr)
        end
      end)

    quote do
      @name unquote(name)
      @schema unquote(body)
    end
  end

  @spec field(t(), atom(), Field.type()) :: t()
  def field(%__MODULE__{fields: fields} = schema, name, type) when is_atom(name) do
    %{schema | fields: Map.put(fields, name, Field.new(name, type))}
  end

  @spec encode(t(), map()) :: iodata()
  def encode(%__MODULE__{fields: fields}, document) do
    known_fields = Map.keys(fields)

    document
    |> Map.take(known_fields)
    |> Enum.map(fn {key, value} -> field_to_iodata(fields[key], value) end)
    |> Enum.reduce([], fn bin, acc -> [acc | bin] end)
  end

  @spec decode!(t(), binary()) :: map()
  def decode!(%__MODULE__{} = schema, content) when is_list(content) do
    content
    |> IO.iodata_to_binary()
    |> then(&decode!(schema, &1))
  end

  def decode!(%__MODULE__{fields: fields}, binary) when is_binary(binary) do
    document = extract_document(binary, %{})

    Enum.reduce(fields, %{}, fn {key, %Field{name: name}}, acc ->
      case Map.get(document, name) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp field_to_iodata(_field, nil), do: []

  defp field_to_iodata(%{type: :text, name: name}, value) when is_binary(value) do
    []
    |> Encoding.put_int(@k_text_tag)
    |> Encoding.put_size_prefixed(name, :tiny)
    |> Encoding.put_size_prefixed(value)
  end

  defp field_to_iodata(%{type: :number, name: name}, value) when is_integer(value) do
    []
    |> Encoding.put_int(@k_integer_tag)
    |> Encoding.put_size_prefixed(name, :tiny)
    |> Encoding.put_int64(value)
  end

  defp field_to_iodata(%{type: :number, name: name}, value) when is_float(value) do
    []
    |> Encoding.put_int(@k_float_tag)
    |> Encoding.put_size_prefixed(name, :tiny)
    |> Encoding.put_float64(value)
  end

  defp field_to_iodata(%{type: :date} = field, value) when is_binary(value) do
    field_to_iodata(field, Date.from_iso8601!(value))
  end

  defp field_to_iodata(%{type: :date, name: name}, %Date{} = date) do
    value = Date.to_gregorian_days(date)

    []
    |> Encoding.put_int(@k_date_tag)
    |> Encoding.put_size_prefixed(name, :tiny)
    |> Encoding.put_int32(value)
  end

  defp field_to_iodata(%{type: :array, name: name}, list) when is_list(list) do
    content =
      Enum.reduce(list, [], fn
        number, acc when is_float(number) ->
          acc
          |> Encoding.put_int(0)
          |> Encoding.put_float64(number)

        number, acc when is_integer(number) ->
          acc
          |> Encoding.put_int(1)
          |> Encoding.put_int64(number)

        value, acc when is_binary(value) ->
          acc
          |> Encoding.put_int(2)
          |> Encoding.put_size_prefixed(value)
      end)

    []
    |> Encoding.put_int(@k_array_tag)
    |> Encoding.put_size_prefixed(name, :tiny)
    |> Encoding.put_size_prefixed(content)
  end

  defp extract_document(<<>>, acc), do: acc

  defp extract_document(binary, acc) do
    {tag, binary} = Encoding.chop_int!(binary)
    {field, binary} = Encoding.chop_size_prefixed!(binary, :tiny)

    {value, binary} =
      case tag do
        @k_text_tag ->
          Encoding.chop_size_prefixed!(binary)

        @k_integer_tag ->
          Encoding.chop_int64!(binary)

        @k_float_tag ->
          Encoding.chop_float64!(binary)

        @k_date_tag ->
          {value, binary} = Encoding.chop_int32!(binary)

          {Date.from_gregorian_days(value), binary}

        @k_array_tag ->
          decode_array(binary)
      end

    extract_document(binary, Map.put(acc, field, value))
  end

  defp decode_array(binary) do
    {value, binary} = Encoding.chop_size_prefixed!(binary)

    fun = fn
      <<>>, _fun, acc ->
        acc

      binary, fun, acc ->
        {element, binary} =
          case Encoding.chop_int!(binary) do
            {0, binary} -> Encoding.chop_float64!(binary)
            {1, binary} -> Encoding.chop_int64!(binary)
            {2, binary} -> Encoding.chop_size_prefixed!(binary)
          end

        fun.(binary, fun, [element] ++ acc)
    end

    value
    |> fun.(fun, [])
    |> Enum.reverse()
    |> then(&{&1, binary})
  end
end
