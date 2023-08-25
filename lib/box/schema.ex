defmodule Box.Schema do
  defstruct [:name, fields: %{}]

  @type literal :: :date | :number | :text
  @type field_type :: literal() | {:array, literal()}

  @type t :: %__MODULE__{
          name: binary(),
          fields: map()
        }

  defmacro schema(name, do: block) when is_binary(name) do
    exprs =
      case block do
        {:__block__, [], exprs} -> exprs
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

  @spec field(t(), atom(), field_type()) :: t()
  def field(%__MODULE__{fields: fields} = schema, name, definition) when is_atom(name) do
    %{schema | fields: Map.put(fields, name, definition)}
  end
end
