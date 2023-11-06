defmodule Box.Schema do
  alias Box.CompactionStrategy.SizeTiered
  alias Box.Field

  defstruct [:name, fields: %{}, compaction_strategy: {SizeTiered, []}]

  @type t :: %__MODULE__{
          name: binary(),
          fields: map(),
          compaction_strategy: {module(), keyword()}
        }

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

  @spec document_to_binary(t(), map()) :: bitstring()
  def document_to_binary(%__MODULE__{fields: fields}, document) do
    known_fields = Map.keys(fields)

    document
    |> Map.take(known_fields)
    |> Enum.map(fn {key, value} -> field_to_binary(fields[key], value) end)
    |> Enum.reduce(<<>>, fn bin, acc -> acc <> bin end)
  end

  @spec binary_to_document(t(), binary()) :: map()
  def binary_to_document(%__MODULE__{fields: fields}, binary) do
    document = extract_document(binary, %{})

    Enum.reduce(fields, %{}, fn {key, %Field{name: name}}, acc ->
      case Map.get(document, name) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp field_to_binary(%Field{}, nil), do: <<>>

  defp field_to_binary(%Field{type: :text, name: name}, value) when is_binary(value) do
    <<1, byte_size(name), byte_size(value)::unsigned-integer-size(64), name::binary,
      value::binary>>
  end

  defp field_to_binary(%Field{type: :number, name: name}, value) when is_integer(value) do
    <<2, byte_size(name), name::binary, value::integer-size(64)>>
  end

  defp field_to_binary(%Field{type: :number, name: name}, value) when is_float(value) do
    <<3, byte_size(name), name::binary, value::float-size(64)>>
  end

  defp field_to_binary(%Field{type: :date} = field, value) when is_binary(value) do
    field_to_binary(field, Date.from_iso8601!(value))
  end

  defp field_to_binary(%Field{type: :date, name: name}, value) when is_struct(value, Date) do
    value = Date.to_gregorian_days(value)

    <<4, byte_size(name), name::binary, value::unsigned-integer-size(24)>>
  end

  defp field_to_binary(%Field{type: {:array, :text}, name: name}, value)
       when is_list(value) do
    value =
      Enum.reduce(value, <<>>, fn a, b ->
        b <> <<byte_size(a)::unsigned-integer-size(64), a::binary>>
      end)

    <<5, byte_size(name), byte_size(value)::unsigned-integer-size(64), name::binary,
      value::binary>>
  end

  defp field_to_binary(%Field{type: {:array, :number}, name: name}, value) do
    value = Enum.reduce(value, <<>>, fn a, b -> b <> <<a::float-size(64)>> end)

    <<6, byte_size(name), byte_size(value)::unsigned-integer-size(64), name::binary,
      value::binary>>
  end

  defp extract_document(<<>>, acc), do: acc

  defp extract_document(
         <<1, k_size::unsigned-integer, v_size::unsigned-integer-size(64),
           field::binary-size(k_size), value::binary-size(v_size), rest::binary>>,
         acc
       ) do
    extract_document(rest, Map.put(acc, field, value))
  end

  defp extract_document(
         <<2, k_size::unsigned-integer, field::binary-size(k_size), value::integer-size(64),
           rest::binary>>,
         acc
       ) do
    extract_document(rest, Map.put(acc, field, value))
  end

  defp extract_document(
         <<3, k_size::unsigned-integer, field::binary-size(k_size), value::float-size(64),
           rest::binary>>,
         acc
       ) do
    extract_document(rest, Map.put(acc, field, value))
  end

  defp extract_document(
         <<4, k_size::unsigned-integer, field::binary-size(k_size),
           value::unsigned-integer-size(24), rest::binary>>,
         acc
       ) do
    value = Date.from_gregorian_days(value)

    extract_document(rest, Map.put(acc, field, value))
  end

  defp extract_document(
         <<5, k_size::unsigned-integer, v_size::unsigned-integer-size(64),
           field::binary-size(k_size), value::binary-size(v_size), rest::binary>>,
         acc
       ) do
    fun = fn
      <<>>, _fun, acc ->
        acc

      <<size::unsigned-integer-size(64), value::binary-size(size), rest::binary>>, fun, acc ->
        fun.(rest, fun, [value] ++ acc)
    end

    value = fun.(value, fun, []) |> Enum.reverse()

    extract_document(rest, Map.put(acc, field, value))
  end

  defp extract_document(
         <<6, k_size::unsigned-integer, v_size::unsigned-integer-size(64),
           field::binary-size(k_size), value::binary-size(v_size), rest::binary>>,
         acc
       ) do
    fun = fn
      <<>>, _fun, acc ->
        acc

      <<num::float-size(64), rest::binary>>, fun, acc ->
        fun.(rest, fun, [num] ++ acc)
    end

    value = fun.(value, fun, []) |> Enum.reverse()

    extract_document(rest, Map.put(acc, field, value))
  end
end
