defmodule Box.Schema do
  alias Box.Field

  defstruct [:name, fields: %{}]

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

  @spec field(t(), atom(), Field.type()) :: t()
  def field(%__MODULE__{fields: fields} = schema, name, type) when is_atom(name) do
    %{schema | fields: Map.put(fields, name, %Field{type: type})}
  end
end
